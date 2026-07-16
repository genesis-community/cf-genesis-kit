package Genesis::Hook::CloudConfig::CF v3.1.0;

use v5.20;
use warnings;

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . '/.genesis/lib' }

use parent qw(Genesis::Hook::CloudConfig);

use Genesis qw/bail/;
use Genesis::Hook::CloudConfig::Helpers qw/gigabytes megabytes/;
use JSON::PP;

sub init {
	my $class = shift;
	my $obj   = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0');
	return $obj;
}

sub perform {
	my ($self) = @_;
	return 1 if $self->completed;

	# The HAProxy default is IaaS-aware: opt-out on aws/gcp/azure (platform LB
	# fronts the routers), default-on elsewhere. This hook keys haproxy static
	# IP / edge sizing on want_feature('haproxy'), which reads the raw env
	# feature list, so resolve it here for consistency with blueprint + features.
	#   - explicit 'haproxy' keeps haproxy on any IaaS (no double-add)
	#   - opt out with 'no-haproxy' (alias 'external-lb'; deprecated 'omit-haproxy')
	#   - listing both is a hard error
	$self->_resolve_haproxy_default();

	# Determine the current IaaS
	my $vm_matrix = $self->get_matrix_for_iaas();

	# PVE always uses BOSH-internal db + blobstore (derived in blueprint.pm);
	# those derived features don't propagate to this hook's feature list, so
	# keep their vm types for pve regardless of the wanted-feature check.
	my $pve = $self->iaas eq 'pve';

	delete( $vm_matrix->{database} )
		unless $pve
		or $self->wants_feature('+internal-db')
		or $self->wants_feature('internal-db');

	delete( $vm_matrix->{blobstore} )
		unless $pve
		or $self->wants_feature('+internal-blobstore')
		or $self->wants_feature('internal-blobstore');

	my @networks                 = ();
	my $network_cloud_properties = {
		openstack => {
			'net_id' => $self->network_reference('id'),   # TODO: $self->subnet_reference('net_id'),
			'security_groups' => ['default'] #$self->subnet_reference('sgs', 'get_security_groups'),
		},
		stackit => {
			'net_id'          => $self->subnet_reference('network_id'),
			'security_groups' => $self->get_network_security_groups(),
		},
		aws => {
			'subnet' => $self->subnet_reference('id'),
			'security_groups' => $self->get_network_security_groups(),
		},
		pve => {
			'bridge' => $self->_pve_cpi_setting('pve_network_bridge', 'network_bridge'),
		},
	};

	if ($self->env->ocfp_config_lookup('net.topology', 'v2') eq 'v1') {
		# OCFP v1 topology - ocf uses up entire available subnet
		$self->relinquish_networks(qw/ocf-core ocf-edge ocf-tcp ocf-runtime ocf-db/);
		@networks = $self->network_definition(
			'ocf',
			strategy       => 'ocfp',
			name_prefix    => $self->env->name . '-',
			greedy_subnets => {
				cloud_properties_for_iaas => $network_cloud_properties,
			}
		);
	} elsif ( $self->want_feature('partitioned-network') ) {
		$self->relinquish_networks('ocf');
		@networks = (
			$self->network_definition(
				'ocf-core',
				strategy        => 'ocfp',
				dynamic_subnets => {
					cloud_properties_for_iaas => $network_cloud_properties,
					allocation => {
						size => $self->for_scale({
							dev  => 8,
							prod => 11
						}),
						statics => 0
					}
				}
			),
			$self->network_definition(
				'ocf-edge',
				strategy        => 'ocfp',
				dynamic_subnets => {
					cloud_properties_for_iaas => $network_cloud_properties,
					allocation => {
						size => $self->for_scale({
							dev  => 1 + ($self->want_feature('haproxy') ? 1 : 0),
							prod => 5 + ($self->want_feature('haproxy') ? 2 : 0)
						}),
						statics => $self->for_scale({
							dev  => 1 + ($self->want_feature('haproxy') ? 1 : 0),
							prod => 5 + ($self->want_feature('haproxy') ? 2 : 0)
						})
					}
				}
			),
			$self->want_feature('no-tcp-router') ? () :
			$self->network_definition(
				'ocf-tcp',
				strategy        => 'ocfp',
				dynamic_subnets => {
					cloud_properties_for_iaas => $network_cloud_properties,
					allocation => {
						size => $self->for_scale({
							dev  => 1,
							prod => 3
						}),
						statics => $self->for_scale({
							dev  => 1,
							prod => 3
						})
					}
				}
			),
			$self->want_feature('+internal-db') ?
			$self->network_definition(
				'ocf-db',
				strategy        => 'ocfp',
				dynamic_subnets => {
					subnets                   => ['ocfp-0'],
					cloud_properties_for_iaas => $network_cloud_properties,
					allocation                => { size => 1, statics => 0 }
				}
			) : (),
			$self->network_definition(
				'ocf-runtime',
				strategy        => 'ocfp',
				dynamic_subnets => {
					cloud_properties_for_iaas => $network_cloud_properties,
					allocation => {
						size => $self->for_scale({
							dev  => $self->get_config_override('diego_cells_per_subnet',  4), #  12 diego cell vms max
							prod => $self->get_config_override('diego_cells_per_subnet', 40)  # 120 diego cell vms max
						}),
						statics => 0
					}
				}
			)
		);
	}
	else {
		$self->relinquish_networks(qw/ocf-core ocf-edge ocf-tcp ocf-runtime ocf-db/);

		# On PVE the SDN vnet is a flat net — all three ocfp-* subnets share the
		# same CIDR, so genesis IPAM tracks claims by (network, subnet-name) only.
		# The BOSH director compilation network is pinned to ocfp-2; restricting
		# the CF workload network to ocfp-0/1 prevents net-compilation IP
		# exhaustion ("no more available") on the shared address space.
		# AWS/STACKIT/OpenStack/vSphere use physically distinct CIDRs per subnet
		# so they are unaffected and must continue spanning all subnets.
		my @ocf_subnets = $self->iaas eq 'pve' ? ('ocfp-0', 'ocfp-1') : ();

		@networks = $self->network_definition(
			'ocf',
			strategy        => 'ocfp',
			dynamic_subnets => {
				(@ocf_subnets ? (subnets => \@ocf_subnets) : ()),
				cloud_properties_for_iaas => $network_cloud_properties,
				allocation => {
					size    => $self->for_scale({
						dev => 10
							+ ($self->want_feature('no-tcp-router') ? 0 : 1)
							+ ($self->get_config_override('diego_cells_per_subnet', 4)),
						prod => 20
							+ ($self->want_feature('no-tcp-router') ? 0 : 5)
							+ ($self->get_config_override('diego_cells_per_subnet', 40))
					}),
					statics => $self->iaas =~ /^(aws)$/ ? 0 : $self->for_scale({
						dev => 1 # router
							+ ($self->want_feature('no-tcp-router') ? 0 : 1)
							+ ($self->want_feature('haproxy')       ? 1 : 0)
							+ ($self->want_feature('+internal-db')  ? 1 : 0),
						prod => 5 # routers
							+ ($self->want_feature('no-tcp-router') ? 0 : 5)
							+ ($self->want_feature('haproxy')       ? 2 : 0)
							+ ($self->want_feature('+internal-db')  ? 1 : 0)
					})
				}
			}
		);
		# NOTE: the partitioned-network branch above (ocf-core, ocf-edge,
		# ocf-tcp, ocf-runtime) similarly spans all subnets.  Apply the same
		# @ocf_subnets guard there if the partitioned topology is ever used on
		# PVE to avoid the same compilation-subnet contention.
	}

	if ($self->want_feature('vip')) { # Maybe add alias for 'public-network'
		push @networks, $self->network_definition(
			'vip',
			strategy => 'vip',
		);
	}

	my $config = $self->build_cloud_config({
		'networks' => \@networks,
		'vm_types' => [(map {
			do {
				# Sanitize vm_type name to a valid config-key segment:
				# lowercase, non-alnum runs collapsed to '_'.
				my $vmk = do { (my $k = lc($_)) =~ s/[^a-z0-9]+/_/g; $k };
				$self->vm_type_definition(
					$_,
					cloud_properties_for_iaas => {
						openstack => {
							'instance_type' => $self->for_scale(
								{
									dev  => $vm_matrix->{$_}{type_dev},
									prod => $vm_matrix->{$_}{type_prod}
								}
							),
							'ephemeral_disk'   => { encrypted => $self->TRUE },
							'boot_from_volume' => $self->TRUE,
							'root_disk' => { size => $vm_matrix->{$_}{disk_size} + 0 }
							,    # Force conversion to integer
						},
						stackit => {
							'instance_type' => $self->for_scale(
								{
									dev  => $vm_matrix->{$_}{type_dev},
									prod => $vm_matrix->{$_}{type_prod}
								}
							),
							'ephemeral_disk'   => { encrypted => $self->TRUE },
							'boot_from_volume' => $self->TRUE,
							'root_disk' => { size => $vm_matrix->{$_}{disk_size} + 0 },
						},
						aws => {
							'instance_type' => $self->for_scale(
								{
									dev  => $vm_matrix->{$_}{type_dev},
									prod => $vm_matrix->{$_}{type_prod}
								}
							),
							'ephemeral_disk' => {
								encrypted => $self->TRUE,
								size      => $self->for_scale(
									{
										dev  => $vm_matrix->{$_}{ephemeral_dev},
										prod => $vm_matrix->{$_}{ephemeral_prod}
									}, 4096
								),
								type => 'gp3'
							},
							'metadata_options' => {
								'http_tokens' => 'required'
							},
						},
						pve => {
							'cpu'            => scalar($self->env->lookup(
								"bosh-configs.cpi.pve_${vmk}_cpu",
								$self->for_scale(
									{
										dev  => $vm_matrix->{$_}{cpu_dev},
										prod => $vm_matrix->{$_}{cpu_prod}
									}, 1
								)
							)),
							'ram'            => scalar($self->env->lookup(
								"bosh-configs.cpi.pve_${vmk}_ram",
								$self->for_scale(
									{
										dev  => $vm_matrix->{$_}{ram_dev},
										prod => $vm_matrix->{$_}{ram_prod}
									}, 1024
								)
							)),
							'disk'           => scalar($self->env->lookup(
								"bosh-configs.cpi.pve_${vmk}_disk",
								$self->for_scale(
									{
										dev  => $vm_matrix->{$_}{disk_dev},
										prod => $vm_matrix->{$_}{disk_prod}
									}, 8192
								)
							)),
							'network_bridge' => $self->_pve_cpi_setting('pve_network_bridge', 'network_bridge'),
						},
					}
				);
			} } ( sort keys %$vm_matrix )),
		],
		'vm_extensions' => [
#			$self->vm_extension_definition('cf-ssh-lb' => {
#				aws => {
#					'lb_target_groups' => ['ocfp-ocf-cf-ssh-lb-tg'],
#				},
#			}),
			$self->vm_extension_definition('cf-system-apps-lb' => {
				aws =>, {
					'lb_target_groups' => ['ocfp-ocf-cf-system-apps-lb-tg','ocfp-ocf-cf-ssh-lb-tg'],
				,},
			},),
			$self->vm_extension_definition('cf-tcp-lb' =>, {
				aws => {
					'lb_target_groups' => ['ocfp-ocf-cf-tcp-lb-tg'],
				},
			}),
			$self->vm_extension_definition('cf-tcp-elb' => {
				aws => {
					'elbs'             => ['ocfp-ocf-cf-tcp-lb'],
				},
			}),
			# PVE has no IaaS LB/security-group layer; emit these as empty
			# extensions so instance groups referencing them still validate.
			$self->vm_extension_definition('cf-router-network-properties' => {
				stackit => {
					'security_groups' => [$self->env->name.'-cf-router-ingress'],
				},
				pve => {},
			}),
			$self->vm_extension_definition('cf-tcp-router-network-properties' => {
				stackit => {
					'security_groups' => [$self->env->name.'-cf-tcp-router-ingress'],
				},
				pve => {},
			}),
			$self->vm_extension_definition('diego-ssh-proxy-network-properties' => {
				stackit => {
					'security_groups' => [$self->env->name.'-cf-ssh-ingress'],
				},
				pve => {},
			}),
		],
		'disk_types' => [
			# PVE always uses BOSH-internal db + blobstore (derived in
			# blueprint.pm); those derived features don't propagate to this
			# hook's feature list, so emit their disk types for pve directly.
			($self->want_feature('+internal-db') || $self->iaas eq 'pve') ?
			$self->disk_type_definition(
				'database',
				common => {
					disk_size => gigabytes(10),
				},
				cloud_properties_for_iaas => {
					openstack => {
						'type' => 'storage_premium_perf6',
					},
					stackit => {
						'type' => 'storage_premium_perf6',
					},
					aws => {
						'type'      => 'gp3',
						'encrypted' => $self->TRUE
					},
					pve => {
						'storage'     => $self->_pve_cpi_setting('pve_disk_storage', 'disk_storage'),
						'disk_format' => $self->_pve_cpi_setting('pve_disk_format', 'disk_format', 'raw'),
					},
				},
			) : (),
			($self->want_feature('+internal-blobstore') || $self->iaas eq 'pve') ?
			$self->disk_type_definition(
				'blobstore',
				common => {
					disk_size => $self->for_scale(
						{
							dev  => gigabytes(100),
							prod => gigabytes(200),
						},
						gigabytes(100)
					)
				},
				cloud_properties_for_iaas => {
					openstack => {
						'type' => 'storage_premium_perf6',
					},
					stackit => {
						'type' => 'storage_premium_perf6',
					},
					aws => {
						'type'      => 'gp3',
						'encrypted' => $self->TRUE
					},
					pve => {
						'storage'     => $self->_pve_cpi_setting('pve_disk_storage', 'disk_storage'),
						'disk_format' => $self->_pve_cpi_setting('pve_disk_format', 'disk_format', 'raw'),
					},
				},
			): (),
		],
	});
	return $self->done($config);
}

sub get_matrix_for_iaas {
	my ($self) = @_;
	my $iaas = $self->iaas;
	my $matrix_method = "_get_${iaas}_vm_matrix";
	return $self->$matrix_method() if ($self->can($matrix_method));

	$self->kit_bug(
		"Unsupported IaaS type '$iaas' for VM matrix. ",
		"Please ensure the IaaS is supported by this kit."
	);
}

sub _get_stackit_vm_matrix {
	my ($self) = @_;
	return {
		map { ( $_->[0], { type_dev => $_->[1], type_prod => $_->[2], disk_size => int($_->[3]) } ) } (
			#     Name           dev_type  prod_type           root_disk_size
			[qw[  api            c2i.4     c1a.4d              15  ]],    #  c1a.4d
			[qw[  cc-worker      c2i.1     c1a.1d              15  ]]
			,    #  a1cpu_2ram_d     =  c1a.1d
			[qw[  credhub        c2i.1     c1a.1d              30  ]],    #  a1cpu_2ram_d
			[qw[  diego-api      c2i.1     c1a.1d              15  ]],    #  a1cpu_2ram_d
			[qw[  diego-cell      g1.4    m1a.16d             256  ]]
			,    #  a16cpu_128ram_d  =  m1a.16d
			[qw[  doppler        c2i.2     c1a.2d              15  ]],    #  a2cpu_4ram_d
			[qw[  errand          c1.1       c1.1              15  ]],    #
			[qw[  log-api        c2i.1     c1a.1d              15  ]],    #  a1cpu_2ram_d
			[qw[  log-cache      c2i.2     c1a.2d              15  ]]
			,    #  a2cpu_4ram_d     =  c1a.2d
			[qw[  nats           c2i.1     c1a.1d              15  ]],    #  a1cpu_2ram_d
			[qw[  router         c2i.4     c1a.4d              15  ]],    #  c1a.4d
			[qw[  scheduler      c2i.1     c1a.1d              15  ]],    #  a1cpu_2ram_d
			[qw[  tcp-router      c1.1       c1.1              10  ]],    #  c1.1
			[qw[  uaa            c2i.2     c1a.2d              30  ]],    #  a2cpu_4ram_d
			[qw[  database       c2i.4     g1a.8d              60  ]],    #  database
			[qw[  blobstore      c2i.1     c1a.1d              60  ]],    #  a1cpu_2ram_d
		)
	}
}

sub _get_pve_vm_matrix {
	# PVE single-node lab sizing. Values are integers consumed by the pve
	# branch of vm_type cloud_properties (cpu, ram[MiB], disk[MiB]).
	# Dev row sized for a single large PVE node (e.g. sm-0, ~1.5 TiB RAM);
	# prod row scaled wider — adjust when multi-node PVE arrives.
	#
	# Disk sizing rule: PVE VMs get NO separate ephemeral disk, so the BOSH
	# agent carves the ROOT disk into ~5G system (root/home) + swap
	# (min(ram, half of the remainder)) + the rest as /var/vcap/data. Keep
	#   disk >= ram + 5120 + intended data space
	# with data space never below ~2G, or jobs have nowhere to unpack.
	# Diego cells additionally lose a grootfs store reserve out of data and
	# must cover staging disk requests: a 16G-RAM cell at 32G disk leaves the
	# rep advertising ~4G and cf push fails with InsufficientResources; 64G
	# yields ~39G data / ~33G advertised.
	my ($self) = @_;
	return {
		map { ( $_->[0], {
			cpu_dev  => int($_->[1]), ram_dev  => int($_->[2]), disk_dev  => int($_->[3]),
			cpu_prod => int($_->[4]), ram_prod => int($_->[5]), disk_prod => int($_->[6]),
		} ) } (
			#     Name         cpu_dev  ram_dev  disk_dev   cpu_prod  ram_prod  disk_prod
			[qw[  api            1       2048    16384       4         8192     32768  ]],
			[qw[  cc-worker      1       1024     8192       2         4096     16384  ]],
			[qw[  credhub        1       2048    16384       2         4096     32768  ]],
			[qw[  diego-api      1       1024     8192       4         8192     16384  ]],
			[qw[  diego-cell     2      16384    65536       8        16384    102400  ]],
			[qw[  doppler        1       1024     8192       2         4096     16384  ]],
			[qw[  errand         1       1024     8192       1         2048     16384  ]],
			[qw[  log-api        1       1024     8192       2         4096     16384  ]],
			[qw[  log-cache      1       2048    16384       4         8192     16384  ]],
			[qw[  nats           1       1024     8192       2         2048     16384  ]],
			[qw[  router         1       1024     8192       2         4096     16384  ]],
			[qw[  scheduler      1       1024     8192       2         4096     16384  ]],
			[qw[  tcp-router     1       1024     8192       2         4096     16384  ]],
			[qw[  uaa            1       2048    16384       2         4096     32768  ]],
			[qw[  database       1       2048    16384       4         8192     65536  ]],
			[qw[  blobstore      1       1024    16384       2         4096     65536  ]],
			[qw[  haproxy        1       1024     8192       2         2048    16384  ]],
		)
	}
}

sub _get_aws_vm_matrix {
	# This is the VM matrix for AWS IaaS.
	my ($self) = @_;
	return {
		map {( $_->[0], {type_dev => $_->[1], type_prod => $_->[2], disk_size => int($_->[3]), ephemeral_dev => int($_->[4]), ephemeral_prod => int($_->[5])}) } (
			#      Name          dev_type     prod_type          root_disk(MB)  ephemeral_dev  ephemeral_prod
			[ qw[  api           t3.medium    m6i.xlarge         15360          32768          65536  ] ],
			[ qw[  cc-worker     t3.medium    m6i.large          15360           8192          16384  ] ],
			[ qw[  credhub       t3.medium    r6i.large          30720           4096          16384  ] ],
			[ qw[  diego-api     t3.large     c6i.2xlarge        15360           4096          16384  ] ],
			[ qw[  diego-cell    t3.large     r6i.4xlarge       262144          65536         393216  ] ],
			[ qw[  doppler       t3.medium    c6i.xlarge         15360           4096          16384  ] ],
			[ qw[  errand        t3.medium    m6i.large          15360           4096           8192  ] ],
			[ qw[  log-api       t3.medium    c6i.xlarge         15360           8192          16384  ] ],
			[ qw[  log-cache     t3.large     r6i.2xlarge        15360           8192          32768  ] ],
			[ qw[  nats          t3.medium    m6i.large          15360           8192          16384  ] ],
			[ qw[  router        t3.medium    c6i.xlarge         15360           4096          16384  ] ],
			[ qw[  scheduler     t3.medium    m6i.large          15360           8192          16384  ] ],
			[ qw[  tcp-router    t3.medium    c6i.xlarge         10240           4096          16384  ] ],
			[ qw[  uaa           t3.large     c6i.large          30720           8192          16384  ] ],
			[ qw[  database      t3.medium    m6i.xlarge         61440           4096          16384  ] ],
			[ qw[  blobstore     t3.medium    m6i.large          61440           4096           8192  ] ],
			[ qw[  windows-cell  t3.large     r6i.2xlarge       262144          65536         393216  ] ],
		)
	}
}

# _pve_cpi_setting - resolve a PVE cloud property from the environment file,
# falling back to the bloc's OCFP CPI config in vault (written by `ocfp vault
# populate`). There is no literal default: PVE bridge and storage names are
# site-specific, so an unset value is a configuration error, not something a
# kit can guess. {{{
sub _pve_cpi_setting {
	my ($self, $env_key, $vault_key, $default) = @_;
	my $value = scalar($self->env->lookup("bosh-configs.cpi.$env_key", undef));
	$value //= scalar($self->env->ocfp_config_lookup("cpi.pve.$vault_key", undef));
	$value //= $default;
	bail(
		"No PVE %s configured for %s: set #c{bosh-configs.cpi.%s} in the ".
		"environment file, or run #g{ocfp vault populate} so the OCFP config ".
		"provides #c{cpi/pve:%s}.",
		$vault_key, $self->env->name, $env_key, $vault_key
	) unless defined($value) && length($value);
	return $value;
}

# }}}
# _resolve_haproxy_default - IaaS-aware haproxy default with explicit override {{{
sub _resolve_haproxy_default {
	my ($self) = @_;

	my %opt_out = map { ($_ => 1) } qw/no-haproxy external-lb omit-haproxy/;
	my @current = $self->features;
	my ($opt_out_marker) = grep { $opt_out{$_} } @current;
	my $has_haproxy = grep { $_ eq 'haproxy' } @current;

	bail(
		"Conflicting features: environment #C{%s} lists both #c{haproxy} and ".
		"#c{%s}.\nKeep #c{haproxy} to deploy the kit-managed haproxy, or keep ".
		"#c{%s} to expose\nthe routers for an external load balancer -- not both.",
		$self->env->name, $opt_out_marker, $opt_out_marker
	) if $has_haproxy && $opt_out_marker;

	# On aws, gcp, and azure the platform load balancer fronts the routers, so
	# haproxy defaults to opt-out there; on all other IaaSes it defaults to on.
	my $iaas_defaults_off = ($self->iaas // '') =~ /^(aws|gcp|azure)$/;

	if ($opt_out_marker || ($iaas_defaults_off && !$has_haproxy)) {
		# No haproxy: strip it so no static IP / edge allocation is added. Drop
		# the opt-out markers; they are not real cloud-config features.
		$self->set_features(grep { $_ ne 'haproxy' && !$opt_out{$_} } @current);
		return;
	}

	# Default-on: add haproxy unless explicitly requested already (no double-add).
	$self->set_features(@current, 'haproxy') unless $has_haproxy;
	return;
}

# }}}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
