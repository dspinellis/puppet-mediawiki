# Class: mediawiki
#
# This class includes all resources regarding installation and configuration
# that needs to be performed exactly once and is therefore not mediawiki
# instance specific.
#
# === Parameters
#
# [*server_name*]      - the host name of the server
# [*admin_email*]      - email address Apache will display when rendering error page
# [*db_root_password*] - password for mysql root user
# [*doc_root*]         - the DocumentRoot directory used by Apache
# [*tarball_url*]      - the url to fetch the mediawiki tar archive
# [*package_ensure*]   - state of the package
# [*max_memory*]       - a memcached memory limit
#
# === Examples
#
# class { 'mediawiki':
#   server_name      => 'www.example.com',
#   admin_email      => 'admin@puppetlabs.com',
#   db_root_password => 'really_really_long_password',
#   max_memory       => '1024'
# }
#
# mediawiki::instance { 'my_wiki1':
#   db_name     => 'wiki1_user',
#   db_password => 'really_long_password',
# }
#
## === Authors
#
# Martin Dluhos <martin@gnu.org>
#
# === Copyright
#
# Copyright 2012 Martin Dluhos
#
define mediawiki::manage_extension(
  $ensure,
  $instance,
  $source,
  $doc_root
 ){
  $extension = $name
  $line = "require_once( \"${doc_root}/${instance}/extensions/ConfirmAccount/ConfirmAccount.php\" );"
  $path = "${doc_root}/${instance}/LocalSettings.php"
 
  mediawiki_extension { $extension:
    ensure    =>  present,
    instance  =>  $wiki_name,
    source    =>  $source,
    doc_root  =>  $doc_root, 
    notify  =>  Exec["set_${extension}_perms"],
  }

  file_line{"${extension}_include":
    line    =>  $line,
    ensure  =>  $ensure,
    path    =>  $path,
    require =>  Mediawiki_extension['ConfirmAccount'],
    notify  =>  Exec["set_${extension}_perms"],
  }
  File_line["${extension}_include"] ~> Service<| title == 'httpd' |>
  exec{"set_${extension}_perms":
    command     =>  "/bin/chown -R ${apache::params::user}:${apache::params::user} ${doc_root}/${instance}",
    refreshonly =>  true,
    notify  =>  Exec["set_${extension}_perms_two"],
  }
  exec{"set_${extension}_perms_two":
    command     =>  "/bin/chown -R ${apache::params::user}:${apache::params::user} /etc/mediawiki/${instance}",
    refreshonly =>  true,
    notify  =>  Exec["set_${extension}_perms_three"],
  }
  exec{"set_${extension}_perms_three":
    command     =>  "/bin/chown -R ${apache::params::user}:${apache::params::user} /var/www/html/mediawiki*",
    refreshonly =>  true
  }
}

class mediawiki (
  $server_name,
  $admin_email,
  $db_root_password,
  $doc_root       = $mediawiki::params::doc_root,
  $tarball_url    = $mediawiki::params::tarball_url,
  $package_ensure = 'latest',
  $max_memory     = '2048'
  ) inherits mediawiki::params {

  $web_dir = $mediawiki::params::web_dir

  # Parse the url
  $tarball_dir              = regsubst($tarball_url, '^.*?/(\d\.\d+).*$', '\1')
  $tarball_name             = regsubst($tarball_url, '^.*?/(mediawiki-\d\.\d+.*tar\.gz)$', '\1')
  $mediawiki_dir            = regsubst($tarball_url, '^.*?/(mediawiki-\d\.\d+\.\d+).*$', '\1')
  $mediawiki_install_path   = "${web_dir}/${mediawiki_dir}"
  
  # Specify dependencies
  Class['mysql::server'] -> Class['mediawiki']
  #Class['mysql::config'] -> Class['mediawiki']

  ensure_resource('class', 'apache',
    { mpm_module => 'prefork' },
  )
  ensure_resource('class', 'apache::mod::php')


  # Manages the mysql server package and service by default
  ensure_resource('class', 'mysql::server',
    { 'root_password' => $db_root_password },
  )

  ensure_resource('package', $mediawiki::params::packages, {
    ensure  => $package_ensure,
  })

  Package[$mediawiki::params::packages] ~> Service<| title == $mediawiki::params::apache |>

  # Make sure the directories and files common for all instances are included
  file { 'mediawiki_conf_dir':
    ensure  => 'directory',
    path    => $mediawiki::params::conf_dir,
    owner   => $apache::params::user,
    group   => $apache::params::group,
    mode    => '0755',
    require => Package[$mediawiki::params::packages],
  }  
  
  # Download and install MediaWiki from a tarball
  exec { "get-mediawiki":
    cwd       => $web_dir,
    command   => "/usr/bin/wget ${tarball_url}",
    creates   => "${web_dir}/${tarball_name}",
    subscribe => File['mediawiki_conf_dir'],
  }
    
  exec { "unpack-mediawiki":
    cwd       => $web_dir,
    command   => "/bin/tar -xvzf ${tarball_name}",
    creates   => $mediawiki_install_path,
    subscribe => Exec['get-mediawiki'],
  }
  
  class { 'memcached':
    max_memory => $max_memory,
    max_connections => '1024',
  }
} 
