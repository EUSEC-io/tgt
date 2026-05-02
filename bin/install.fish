#!/usr/bin/env fish
# Symlink the loader into fish's conf.d. Idempotent.

set -l self (realpath (status filename))
set -l repo (dirname (dirname $self))
set -l loader $repo/conf.d/tgt-loader.fish

if not test -f $loader
    echo "error: $loader not found" >&2
    exit 1
end

set -l fish_dir
if test -n "$XDG_CONFIG_HOME"
    set fish_dir $XDG_CONFIG_HOME/fish
else
    set fish_dir $HOME/.config/fish
end

set -l conf_d $fish_dir/conf.d
set -l target $conf_d/tgt-loader.fish

mkdir -p $conf_d

if test -L $target
    set -l existing (realpath $target)
    if test "$existing" = "$loader"
        echo "✓ already installed: $target"
        exit 0
    else
        echo "warning: $target → $existing, overwriting" >&2
    end
else if test -e $target
    echo "error: $target exists and is not a symlink — refusing to overwrite" >&2
    exit 1
end

ln -sf $loader $target
echo "✓ installed: $target → $loader"
echo "  open a new shell, or: source $target"
