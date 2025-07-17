package Genesis::Hook::CloudConfig::CF;

use v5.20;
use warnings;

# Only needed for development
BEGIN { push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME} . '/.genesis/lib' }

use parent qw(Genesis::Hook::CloudConfig);

use Genesis qw//;
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

	# Determine the current IaaS
	my $vm_matrix = $self->get_matrix_for_iaas();

	delete( $vm_matrix->{database} )
		unless $self->wants_feature('+internal-db')
		or $self->wants_feature('internal-db');

	delete( $vm_matrix->{blobstore} )
		unless $self->wants_feature('+internal-blobstore')
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
	};

	if ( $self->want_feature('partitioned-network') ) {
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
		@networks = $self->network_definition(
			'ocf',
			strategy        => 'ocfp',
			dynamic_subnets => {
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
	}

	my $config = $self->build_cloud_config({
		'networks' => \@networks,
		'vm_types' => [(map {
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
				}
			),
		} ( sort keys %$vm_matrix )),
		],
		'vm_extensions' => [
			$self->vm_extension_definition('cf-ssh-lb' => {
				aws => {
					'lb_target_groups' => ['ocfp-ocf-cf-ssh-lb-tg'],
				},
			}),
			$self->vm_extension_definition('cf-system-apps-lb' => {
				aws => {
					'lb_target_groups' => ['ocfp-ocf-cf-system-apps-lb-tg'],
				},
			}),
			$self->vm_extension_definition('cf-tcp-lb' => {
				aws => {
					'lb_target_groups' => ['ocfp-ocf-cf-tcp-lb-tg'],
				},
			}),
			$self->vm_extension_definition('cf-tcp-elb' => {
				aws => {
					'elbs'             => ['ocfp-ocf-cf-tcp-lb'],
				},
			}),
		],
		'disk_types' => [
			$self->want_feature('+internal-db') ?
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
				},
			) : (),
			$self->want_feature('+internal-blobstore') ?
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

sub _get_aws_vm_matrix {
	# This is the VM matrix for AWS IaaS.
	my ($self) = @_;
	return {
		map {( $_->[0], {type_dev => $_->[1], type_prod => $_->[2], disk_size => int($_->[3]), ephemeral_dev => int($_->[4]), ephemeral_prod => int($_->[5])}) } (
			#      Name          dev_type     prod_type          root_disk(MB)  ephemeral_dev  ephemeral_prod
			[ qw[  api           t3.medium    m6i.xlarge         15360          32768          65536  ] ],
			[ qw[  cc-worker     t3.medium    m6i.large          15360           4096           8192  ] ],
			[ qw[  credhub       t3.medium    r6i.large          30720           4096          16384  ] ],
			[ qw[  diego-api     t3.large     c6i.2xlarge        15360           4096          16384  ] ],
			[ qw[  diego-cell    t3.large     r6i.2xlarge       262144          65536         393216  ] ],
			[ qw[  doppler       t3.medium    c6i.xlarge         15360           4096          16384  ] ],
			[ qw[  errand        t3.medium    m6i.large          15360           4096           8192  ] ],
			[ qw[  log-api       t3.medium    c6i.xlarge         15360           8192          16384  ] ],
			[ qw[  log-cache     t3.large     r6i.2xlarge        15360           8192          16384  ] ],
			[ qw[  nats          t3.medium    m6i.large          15360           8192          16384  ] ],
			[ qw[  router        t3.medium    c6i.xlarge         15360           4096          16384  ] ],
			[ qw[  scheduler     t3.medium    m6i.large          15360           4096           8192  ] ],
			[ qw[  tcp-router    t3.medium    c6i.xlarge         10240           4096          16384  ] ],
			[ qw[  uaa           t3.large     c6i.large          30720           4096          16384  ] ],
			[ qw[  database      t3.medium    m6i.xlarge         61440           4096          16384  ] ],
			[ qw[  blobstore     t3.medium    m6i.large          61440           4096           8192  ] ],
			[ qw[  windows-cell  t3.medium    r6i.2xlarge       262144          65536         393216  ] ],
		)
	}
}

1;
# vim: set ts=2 sw=2 sts=2 noet fdm=marker foldlevel=1:
