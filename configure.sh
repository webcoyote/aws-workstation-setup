#!/bin/bash
set -e
set -u

# Check sudo
if [ $(id -u) -eq 0 ]; then
    echo 'ERROR: Do not run this script as sudo'
    exit
fi

function homebrew_install () {
  case "$OSTYPE" in
    darwin*)
      if which brew &>/dev/null; then
        echo homebrew installed
      else
        ruby -e "$(curl -fsSL https://raw.github.com/mxcl/homebrew/go)"
      fi
    ;;
  esac
}

function package_install () {
  # already installed?
  if which $1 &>/dev/null; then
    echo $1 already installed
    return
  fi

  case "$OSTYPE" in
    darwin*)
      brew install "$1"
    ;;

    linux*)
      if which apt-get &>/dev/null ; then
        sudo apt-get install -y "$1"
      elif which yum &>/dev/null ; then
        sudo yum install -y "$1"
      else
        echo "Unknown Linux distro" && exit 1
      fi
    ;;

    *)
      echo Unknown OS: $OSTYPE;
      exit 1
    ;;
  esac
}

function git_update_repo () {
  repo=$1
  dir=$2

  if [ ! -d "$dir" ]; then
    git clone "$repo" "$dir"
  fi

  pushd $dir >/dev/null
  git pull origin master
  popd >/dev/null
}

function github_update_repo () {
  user=$1
  pkg=$2
  dir=$3
  git_update_repo git://github.com/$user/$pkg.git "$dir"/$pkg
}

function install_vagrant_plugin () {
  if ! (vagrant plugin list | grep $1 &>/dev/null) ; then
    vagrant plugin install $1
  fi
}

function get_template () {
  \curl -LsS >$1 https://raw.github.com/webcoyote/aws-workstation-setup/master/templates/$2
}

function create_config_template () {
  if [ ! -f ~/.credentials/$1 ]; then
    get_template ~/.credentials/$1 $1
  fi
}

case "$OSTYPE" in
  darwin*)
    # TrueCrypt doesn't work on the command line
  ;;

  linux*)
    # Ask for truecrypt password
    read -s -p "Enter TrueCrypt password for ~/.TrueCrypt/credentials.tc: " PASSWORD
    echo
    if [ ! -f ~/.TrueCrypt/credentials.tc ]; then
      read -s -p "Please re-enter password: " PASSWORD2
      echo
      if [ "$PASSWORD" != "$PASSWORD2" ]; then
        echo "Passwords don't match"
        exit 1
      fi
    fi
  ;;
esac

# Install packages
homebrew_install
package_install git
package_install ruby

# Install required repos
github_update_repo webcoyote pivotal_workstation ~/.cache/aws-prep/cookbooks
github_update_repo opscode-cookbooks apt ~/.cache/aws-prep/cookbooks
github_update_repo opscode-cookbooks dmg ~/.cache/aws-prep/cookbooks
github_update_repo opscode-cookbooks yum ~/.cache/aws-prep/cookbooks

# Install soloist in system ruby
(which soloist &>/dev/null) || (gem install soloist </dev/null)

# Configure soloist
cd ~/.cache/aws-prep
get_template soloistrc soloistrc

# Run soloist to install other required software, like Vagrant
soloist

# Install vagrant plugins
install_vagrant_plugin vagrant-berkshelf
install_vagrant_plugin vagrant-aws

# Configure TrueCrypt
mkdir -p ~/.TrueCrypt &>/dev/null

case "$OSTYPE" in
  darwin*)
    # TrueCrypt command line provides a cryptic error:
    # "this feature is only supported in text mode"
    # when running from the command line, so ...
    mkdir ~/.credentials &>/dev/null
  ;;

  linux*)
    # Create truecrypt drive for credentials
    if [ ! -f ~/.TrueCrypt/credentials.tc ]; then
      echo "-"
      echo "Creating truecrypt file; takes five minutes :("
      echo "If you move your mouse really quickly it will only take ~30 seconds -- really!"
      echo "-"
      truecrypt-cmd --create --size=$((1024*1024)) --volume-type=normal         \
        --encryption=AES-Twofish-Serpent --hash=RIPEMD-160 --filesystem=fat     \
        -p "$PASSWORD" --keyfiles='' --random-source=/dev/random        \
          ~/.TrueCrypt/credentials.tc
    fi

    # Unmount the credentials file in case it is mounted, then re-mount
    mkdir -p ~/.credentials &>/dev/null
    truecrypt-cmd -d ~/.credentials &>/dev/null || true
    truecrypt-cmd --mount -p "$PASSWORD" --keyfiles='' \
      --protect-hidden=no ~/.TrueCrypt/credentials.tc ~/.credentials
  ;;
esac

# Configure AWS and Perforce
create_config_template p4config
create_config_template awsconfig.yml

echo "Setup complete"
echo
case "$OSTYPE" in
  darwin*)
    echo "Please edit AND ENCRYPT your credentials in ~/.credentials"
  ;;

  *)
    echo "Please edit your credentials files, which are stored in ~/.credentials"
  ;;
esac
