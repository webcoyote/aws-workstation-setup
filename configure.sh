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
  case "$OSTYPE" in
    darwin*)
      for pkg in "$@"; do brew install "$pkg"; done
    ;;

    linux*)
      if which apt-get &>/dev/null ; then
        sudo apt-get install -y "$@"
      elif which yum &>/dev/null ; then
        sudo yum install -y "$@"
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

# Ask for the password up front so the rest of the script just works
sudo true

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
sudo gem install soloist </dev/null

# Configure soloist
cd ~/.cache/aws-prep
\curl -LsS > soloistrc https://raw.github.com/webcoyote/aws-workstation-setup/master/soloistrc

# Run soloist to install other required software, like Vagrant
soloist

# Install vagrant plugins
vagrant plugin install vagrant-berkshelf
vagrant plugin install vagrant-aws

echo "Setup complete"
