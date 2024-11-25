package Genesis::Hook::CloudConfig::CF v2.6.0;

use strict;
use warnings;

# Only needed for development
BEGIN {push @INC, $ENV{GENESIS_LIB} ? $ENV{GENESIS_LIB} : $ENV{HOME}.'/.genesis/lib'}

use parent qw(Genesis::Hook::CloudConfig);

use Genesis::Hook::CloudConfig::Helpers qw/gigabytes megabytes/;

use Genesis qw//;
use JSON::PP;

sub init {
	my $class = shift;
	my $obj = $class->SUPER::init(@_);
	$obj->check_minimum_genesis_version('3.1.0-rc.4');
	return $obj;
}

sub perform {
	my ($self) = @_;
	return 1 if $self->completed;

  my @vm_type_names = qw/
    api cc-worker credhub diego-api diego-cell doppler default log-api log-cache
    nats router scheduler tcp-router uaa
  /;

  my $common_vm_type_def = {
    cloud_properties_for_iaas => {
      openstack => {
        'instance_type' => $self->for_scale({
            dev => 'm1.2',
            prod => 'm1.3'
          }, 'm1.2'),
        'boot_from_volume' => $self->TRUE,
        'root_disk' => {
          'size' => 32 # in gigabytes
        },
      },
    },
  };

	my $config = $self->build_cloud_config({
		'networks' => [
			$self->network_definition('ocf', strategy => 'ocfp',
				dynamic_subnets => {
					allocation => {
						size => 32,
						statics => 8,
					},
					cloud_properties_for_iaas => {
						openstack => {
							'net_id' => $self->network_reference('id'), # TODO: $self->subnet_reference('net_id'),
							'security_groups' => ['default'] #$self->subnet_reference('sgs', 'get_security_groups'),
						},
					},
				},
			)
		],
		'vm_types' => [ map {
        $self->vm_type_definition($_, %$common_vm_type_def)
      } (@vm_type_names)
    ],
		'disk_types' => [
			$self->disk_type_definition('10GB',
				common => {
          disk_size => gigabytes(10),
				},
				cloud_properties_for_iaas => {
					openstack => {
						'type' => 'storage_premium_perf6',
					},
				},
			),
	  	$self->disk_type_definition('100GB',
				common => {
					disk_size => gigabytes(100),
				},
				cloud_properties_for_iaas => {
					openstack => {
						'type' => 'storage_premium_perf6',
					},
				},
			),
		],
	});

	$self->done($config);
}

1;
