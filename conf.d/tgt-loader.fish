# Sourced at shell startup via a symlink in ~/.config/fish/conf.d/.
# Self-locates so the repo can live anywhere on disk.

set -l self (realpath (status filename))
set -l repo (dirname (dirname $self))

for dir in $repo/*/
    test -d $dir; or continue
    set -l name (basename $dir)
    test -f $dir/$name.fish; or continue

    set -p fish_function_path $dir
    test -d $dir/completions; and set -p fish_complete_path $dir/completions
end
