#!/usr/bin/env fish
set -l fish_dir
if test -n "$XDG_CONFIG_HOME"
    set fish_dir $XDG_CONFIG_HOME/fish
else
    set fish_dir $HOME/.config/fish
end

rm -f $fish_dir/conf.d/tgt-loader.fish
echo "✓ removed loader (functions remain on disk)"
