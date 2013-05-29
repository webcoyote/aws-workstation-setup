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

function rbenv_install () {
  if which rbenv &>/dev/null; then
    RBENVDIR=$(dirname $(dirname `which rbenv`))
  else
    case "$OSTYPE" in
      darwin*)
        brew install rbenv ruby-build
        RBENVDIR=(dirname $(dirname `which rbenv`))
      ;;

      linux*)
        # We could use apt-get install rbenv, but ruby-build is not included!
        git_update_repo git://github.com/sstephenson/rbenv ~/.rbenv
        git_update_repo git://github.com/sstephenson/ruby-build ~/.rbenv/plugins/ruby-build
        RBENVDIR=$HOME/.rbenv
      ;;

      *)
        echo Unknown OS: $OSTYPE;
        exit 1
      ;;
    esac
  fi

  export PATH=$RBENVDIR/bin:$PATH
  eval "$(rbenv init -)"
}

function ruby_install () {
  RBENV_VERSION=1.9.3-p429
  if [ ! -d "$RBENVDIR/versions/$RBENV_VERSION" ]; then
    rbenv install "$RBENV_VERSION" --force
  fi
  rbenv shell "$RBENV_VERSION"
}

function soloist_install () {
  if ! which soloist &>/dev/null; then
    gem install soloist </dev/null
  fi
}

function install_vagrant_plugin () {
  if ! (vagrant plugin list | grep $1 &>/dev/null) ; then
    vagrant plugin install $1
  fi
}

function get_template () {
  \curl -LsS > "$1" https://raw.github.com/webcoyote/aws-workstation-setup/master/templates/$(basename $1)
}

function create_config_template () {
  pushd ~/Private/credentials &>/dev/null
  if [ ! -f "$1" ]; then
    get_template "$1"
    ln -s -f "$1" "$2"
  fi
  popd &>/dev/null
}

function truecrypt_prepare () {
  # select truecrypt command
  case "$OSTYPE" in
    darwin*)
      TRUECRYPT="/Applications/TrueCrypt.app/Contents/MacOS/TrueCrypt --text"
    ;;

    linux*)
      TRUECRYPT=truecrypt-cmd
    ;;
  esac

  # Explain what we're going to do
  if [ ! -f ~/.TrueCrypt/credentials.tc ]; then
    echo "This script will create/mount a TrueCrypt directory to contain your AWS"
    echo "and Perforce credentials. Please enter a strong password to secure them."
    echo
  fi

  # Ask for truecrypt password
  read -s -p "Enter password for ~/.TrueCrypt/credentials.tc: " PASSWORD
  echo
  if [ ! -f ~/.TrueCrypt/credentials.tc ]; then
    read -s -p "Re-enter password: " PASSWORD2
    echo
    if [ "$PASSWORD" != "$PASSWORD2" ]; then
      echo "Passwords don't match"
      exit 1
    fi
  fi
}


###############################################################################
#
# Main script
#
####

truecrypt_prepare
homebrew_install
package_install git
rbenv_install
ruby_install
soloist_install

# Install required repos for soloist run
github_update_repo webcoyote pivotal_workstation ~/.cache/aws-prep/cookbooks
github_update_repo opscode-cookbooks apt ~/.cache/aws-prep/cookbooks
github_update_repo opscode-cookbooks dmg ~/.cache/aws-prep/cookbooks
github_update_repo opscode-cookbooks yum ~/.cache/aws-prep/cookbooks

# Configure and run soloist to install software
cd ~/.cache/aws-prep
get_template soloistrc
soloist
install_vagrant_plugin vagrant-berkshelf
install_vagrant_plugin vagrant-aws

# Configure TrueCrypt
mkdir -p ~/.TrueCrypt &>/dev/null

# Create truecrypt drive for credentials
if [ ! -f ~/.TrueCrypt/credentials.tc ]; then
  echo "-"
  echo "Creating truecrypt file; takes five minutes :("
  echo "If you move your mouse really quickly it will only take ~30 seconds -- really!"
  echo "-"
  $TRUECRYPT --create --size=$((1024*1024)) --volume-type=normal            \
    --encryption=AES-Twofish-Serpent --hash=RIPEMD-160 --filesystem=fat     \
    -p "$PASSWORD" --keyfiles='' --random-source=/dev/random                \
      ~/.TrueCrypt/credentials.tc
fi

# Create a directory to store credentials. Set permissions on the parent
# to read/write only for user because the child directory will be a mounted
# DOS "FAT" partition that doesn't support file permissions
mkdir -p ~/Private/credentials &>/dev/null
chmod 0700 ~/Private

# Unmount the credentials file in case it is mounted, then re-mount, in order
# to ensure that folder is mounted properly.
$TRUECRYPT -d ~/Private/credentials &>/dev/null || true
$TRUECRYPT --mount -p "$PASSWORD" --keyfiles='' \
  --protect-hidden=no ~/.TrueCrypt/credentials.tc ~/Private/credentials

# Configure AWS, Fog and Perforce
create_config_template p4config       ~/.p4config
create_config_template awsconfig.yml  ~/.awsconfig
create_config_template fog.yml        ~/.fog

echo "Setup complete"
echo
echo "Please edit your credentials files, which are stored in ~/Private/credentials"
