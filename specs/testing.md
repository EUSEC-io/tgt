# Spec: Testing Strategy

Status: draft
Owner: stefan

## Goal

Get every function under test, including the underscore helpers and the
file-manipulation paths, without:

- requiring `sudo` to run the test suite,
- touching the real `/etc/hosts` or `/etc/krb5.conf`,
- polluting the user's universal fish vars,
- depending on `bloodhound-python` actually being installed.

The project rule says "every function must have a corresponding
`test/test_<name>.fish`". Today there is no `test/` directory at all.
This spec defines how to get there.

## Testing surface

What's worth testing:

| Layer | Examples | Test type |
|---|---|---|
| Pure helpers | krb5 realm parsing, alias name validation | Unit, fast |
| File mutators | `/etc/hosts` add/remove, krb5 realm add/remove | Unit, against tmp files |
| Registry | scenario create/switch/rm, target create/switch/rm | Unit, against tmp `$TGT_HOME` |
| Headless dispatch | `tgt switch foo`, `tgt --revoke`, `tgt scenario rm bar` | Unit |
| Wizard / interactive | `tgt new` prompts | Integration, scripted stdin |
| External tools | `bloodhound-python` invocation | Mocked — verify arg list, don't run |

What we skip:
- Actually running `bloodhound-python`, `sudo`, `zip`. Out of scope for unit tests.
- Real `/etc/hosts` or `/etc/krb5.conf`. Path indirection avoids this.

## Refactor for testability

Three structural changes to make the rest of the strategy possible.

### 1. Path indirection

Every absolute path becomes an env-var override with a sensible default:

```fish
set -l hosts_file (set -q TGT_HOSTS_FILE; and echo $TGT_HOSTS_FILE; or echo /etc/hosts)
set -l krb5_file (set -q TGT_KRB5_FILE; and echo $TGT_KRB5_FILE; or echo /etc/krb5.conf)
set -l tgt_home  (set -q TGT_HOME;       and echo $TGT_HOME;       or echo $HOME/.config/fish/tgt)
```

Production behavior unchanged. Tests `set -lx TGT_HOSTS_FILE (mktemp)`
and the code naturally writes to the temp file. No mocking, no
conditional logic in the code under test.

### 2. Side-effect boundary wrappers

Privileged or external operations go through narrow wrapper functions
we can stub in tests. The wrappers are the only place the convention's
`command sudo` lives.

```fish
function _tgt_hosts_write --argument-names content
    set -l tmp (mktemp)
    printf '%s\n' $content > $tmp
    if set -q TGT_TEST_MODE
        command mv $tmp $hosts_file
    else
        command sudo install -m 644 -o root -g root $tmp $hosts_file
        command rm -f $tmp
    end
end
```

Same shape for `_tgt_krb5_write`. The headless logic builds the desired
file content as a string and hands it to the wrapper — no sudo on the
test path, no `install` (because the test owns the tmp file directly).

Bloodhound stays in `_tgt_run_bloodhound`, which already exists. In
tests, that whole function gets shadowed:

```fish
function _tgt_run_bloodhound
    echo "MOCK: $argv" >> $TGT_TEST_LOG
    return 0
end
```

### 3. Wizard / headless split

Every operation has a pure function that takes args, returns an exit
code, and writes nothing to stdin/stdout except the data the caller
asked for. The interactive wizard is a thin `read`-driven shell on top.

```fish
# functions/_tgt_create_target.fish — pure
function _tgt_create_target --argument-names alias ip port user pass domain dc
    # validate, write registry file, update /etc/hosts, update krb5
    # return 0 / 1
end

# functions/_tgt_wizard.fish — read-driven
function _tgt_wizard
    read -P "  IP: " ip
    read -P "  Port: " port
    # ... etc
    _tgt_create_target $alias $ip $port $user $pass $domain $dc
end
```

90% of the code lives in `_tgt_create_target`-style functions and is
testable with plain arg passing. The wizard is small and tested
separately by piping stdin.

## Mocking strategy

Fish shadows commands and functions by name within scope. Tests
override only what they need to.

### Stubbing externals

```fish
@setup
    # Mock sudo so the wrapper doesn't actually escalate.
    function sudo --inherit-variable TGT_TEST_LOG
        echo "sudo: $argv" >> $TGT_TEST_LOG
        # Pass through to the actual command, sans privilege:
        eval $argv
    end
end
```

For tools we never want to actually run (`bloodhound-python`, `zip`),
the override returns success without calling anything:

```fish
function bloodhound-python
    echo "bloodhound-python: $argv" >> $TGT_TEST_LOG
    # Drop fake JSON files so the zip step has something to find:
    touch users.json computers.json
    return 0
end
```

### Why wrappers + shadows together

The convention says use `command <name>` for externals to defeat shell
aliases. But `command` also bypasses function shadows, which would
defeat tests. Resolution:

- **Helpers** (`_tgt_hosts_write`, `_tgt_run_bloodhound`) call `command sudo`,
  `command bloodhound-python`, etc. — defensive, per convention.
- **Tests** stub the *helpers*, not the commands. We never need to
  shadow `sudo` itself; we shadow `_tgt_hosts_write` to no-op.

The exception is the wizard's `read` prompts, where we *do* want stdin
piped. That's `read`, which fish doesn't let you shadow easily — but
piping stdin to the function works without any mocking.

### Stubbing `read` for wizard tests

```fish
@test "wizard creates target from prompted input" (
    set -lx TGT_TEST_MODE 1
    set -lx TGT_HOME (mktemp -d)
    printf '10.10.11.5\n445\nadmin\nhunter2\nn\n' | _tgt_wizard test-box
    test -f $TGT_HOME/scenarios/default/targets/test-box.fish
)
```

Each newline answers one `read -P` prompt. Order-fragile but explicit.

## Test isolation

Three layers of isolation, layered cheap-to-expensive.

### Per-test tmp dirs (default)

```fish
@setup
    set -gx TGT_TEST_MODE 1
    set -gx TGT_TEST_LOG (mktemp)
    set -gx TGT_HOME (mktemp -d)
    set -gx TGT_HOSTS_FILE (mktemp)
    set -gx TGT_KRB5_FILE (mktemp)
end

@teardown
    rm -rf $TGT_HOME $TGT_HOSTS_FILE $TGT_KRB5_FILE $TGT_TEST_LOG
end
```

This handles the file paths cleanly.

### Universal-var hygiene (the trap)

`set -Ux` writes to fishd's universal-vars file
(`~/.config/fish/fish_variables`) and persists across all your shells.
If a test ever runs `set -Ux TGT 10.10.10.5` for real, you'll find that
variable mysteriously set in every terminal you open for the next year.

All exports in `tgt` go through a wrapper:

```fish
function _tgt_export
    if set -q TGT_TEST_MODE
        set -gx $argv
    else
        set -Ux $argv
    end
end
```

Production: universal scope (multi-tab pentesting workflow stays intact).
Tests: global scope, dies when the fish process ends.

### Subshell isolation (opt-in, for the paranoid tests)

For the handful of tests where universal-var *semantics* actually
matter (e.g. "does `tgt switch` actually expose vars to other shells?"),
spin up a fresh fish with redirected `XDG_CONFIG_HOME`:

```fish
@test "switch persists vars across shells" (
    set -l home (mktemp -d)
    fish -c "
        set -gx XDG_CONFIG_HOME $home/.config
        set -gx TGT_HOME       $home/tgt
        tgt scenario new test
        tgt new web --ip 10.10.10.5
        tgt switch web
    "
    fish -c "
        set -gx XDG_CONFIG_HOME $home/.config
        test \$TGT = 10.10.10.5
    "
)
```

Slower but airtight. Use sparingly.

## Test layout

```
test/
  helpers.fish               # @setup/@teardown shared boilerplate
  fixtures/
    hosts/
      empty.txt
      basic.txt              # one user-managed entry, no tgt entries
      mixed.txt              # tgt + user entries together
      multi-scenario.txt     # entries from two scenarios
    krb5/
      empty.conf
      one-realm.conf
      two-realms.conf
  test_tgt.fish              # top-level dispatch, --revoke, --show
  test__tgt_create_target.fish
  test__tgt_clean_krb5.fish
  test__tgt_update_krb5.fish
  test__tgt_run_bloodhound.fish
  test__tgt_hosts_add.fish
  test__tgt_hosts_remove.fish
  test__tgt_hosts_write.fish
  test__tgt_scenario_new.fish
  test__tgt_scenario_rm.fish
  test__tgt_wizard.fish      # the only one that pipes stdin
  test_integration.fish      # subshell-isolated end-to-end
```

`helpers.fish` exposes shared setup as functions:

```fish
function _test_setup_tmp
    set -gx TGT_TEST_MODE 1
    set -gx TGT_TEST_LOG (mktemp)
    set -gx TGT_HOME (mktemp -d)
    set -gx TGT_HOSTS_FILE (mktemp)
    set -gx TGT_KRB5_FILE (mktemp)
end

function _test_load_fixture --argument-names target src
    cat (status dirname)/fixtures/$src > $$target
end

function _test_teardown
    rm -rf $TGT_HOME $TGT_HOSTS_FILE $TGT_KRB5_FILE $TGT_TEST_LOG
    set -e TGT_TEST_MODE TGT_TEST_LOG TGT_HOME TGT_HOSTS_FILE TGT_KRB5_FILE
end
```

## Concrete examples

### Pure helper

```fish
# test/test__tgt_clean_krb5.fish
source (status dirname)/helpers.fish

@test "removes only the named realm, leaves others intact" (
    _test_setup_tmp
    _test_load_fixture TGT_KRB5_FILE krb5/two-realms.conf

    _tgt_clean_krb5 EXAMPLE.COM

    not string match -q "*EXAMPLE.COM*" (cat $TGT_KRB5_FILE)
    string match -q "*OTHER.LOCAL*" (cat $TGT_KRB5_FILE)
    _test_teardown
)

@test "is a no-op when realm absent" (
    _test_setup_tmp
    _test_load_fixture TGT_KRB5_FILE krb5/one-realm.conf
    set -l before (md5sum $TGT_KRB5_FILE)

    _tgt_clean_krb5 NEVER.SEEN

    set -l after (md5sum $TGT_KRB5_FILE)
    test "$before" = "$after"
    _test_teardown
)
```

### File mutation

```fish
# test/test__tgt_hosts_add.fish
source (status dirname)/helpers.fish

@test "appends hostname to existing tagged line" (
    _test_setup_tmp
    _test_load_fixture TGT_HOSTS_FILE hosts/multi-scenario.txt

    _tgt_hosts_add dante web01 newhost.dante.local

    set -l line (string match -r '.*tgt:dante:web01$' < $TGT_HOSTS_FILE)
    string match -q "*newhost.dante.local*" -- $line
    _test_teardown
)

@test "creates new tagged line when target has no entry yet" (
    _test_setup_tmp
    _test_load_fixture TGT_HOSTS_FILE hosts/basic.txt

    _tgt_hosts_add acme webapp api.acme.test 10.20.30.5

    grep -q "10.20.30.5.*tgt:acme:webapp" $TGT_HOSTS_FILE
    _test_teardown
)

@test "leaves user-managed lines untouched" (
    _test_setup_tmp
    _test_load_fixture TGT_HOSTS_FILE hosts/mixed.txt
    set -l user_line_count (string match -r '^[^#].*$' < $TGT_HOSTS_FILE | string match -rv 'tgt:' | count)

    _tgt_hosts_add dante web01 something.test

    set -l user_line_count_after (string match -r '^[^#].*$' < $TGT_HOSTS_FILE | string match -rv 'tgt:' | count)
    test $user_line_count = $user_line_count_after
    _test_teardown
)
```

### External tool (mocked)

```fish
# test/test__tgt_run_bloodhound.fish
source (status dirname)/helpers.fish

@test "passes correct args to bloodhound-python" (
    _test_setup_tmp
    set -gx TGT 10.10.10.5
    set -gx TGT_DC_DOMAIN htb.local
    set -gx TGT_DC DC01.htb.local

    function bloodhound-python --inherit-variable TGT_TEST_LOG
        echo "called: $argv" >> $TGT_TEST_LOG
        return 0
    end

    _tgt_run_bloodhound admin hunter2 all false out.zip

    grep -q "\-u admin"          $TGT_TEST_LOG
    grep -q "\-p hunter2"        $TGT_TEST_LOG
    grep -q "\-d htb.local"      $TGT_TEST_LOG
    grep -q "\-ns DC01.htb.local" $TGT_TEST_LOG
    _test_teardown
)
```

## Tooling

- **Runner**: Fishtape (already in CLAUDE.md). No alternative needed.
- **Make target**: `make test` runs `fishtape test/test_*.fish`.
- **CI**: not a priority for a personal toolkit, but a GitHub Actions
  workflow running `apt-get install fish && make test` on push is ten
  lines if we ever want it.
- **Coverage**: fish has no native coverage tool. Skip — TAP output is
  enough signal for a personal repo.

## Decisions

- **Export wrapper**: use `_tgt_export`. Production routes to `set -Ux`,
  `TGT_TEST_MODE=1` routes to `set -gx`. Single chokepoint, no scattered
  `if test` checks.
- **`--no-bh` flag for the test runner**: yes, but defer implementation
  until BloodHound integration tests actually exist. Mocked unit tests
  don't need to be skipped — they don't shell out.
- **Fixtures**: hand-written. See "Fixture authoring" below.

## Fixture authoring

Fixtures are literal files in `test/fixtures/` that represent realistic
starting states for `/etc/hosts` and `/etc/krb5.conf`. Tests
`cat fixtures/foo.txt > $TGT_HOSTS_FILE` and proceed.

### Why hand-written

- Format is stable — `/etc/hosts` is RFC, `/etc/krb5.conf` is MIT.
  Rewriting fixtures is rare.
- A test reading `multi-scenario.txt` is immediately understandable.
  A test reading `_test_make_hosts --scenario dante --target web01 ...`
  forces you to mentally reconstruct what file you're operating on.
- Diffing actual vs. expected output is trivial when both are flat text.
  When state is generated, diffs become meaningless without a renderer.

### Naming convention

`fixtures/<file>/<state>.<ext>` where `<state>` is a short snake_case
description of what's in the file.

### `/etc/hosts` fixtures

The set we'll need:

**`fixtures/hosts/empty.txt`** — completely empty, for first-run tests.

```

```

**`fixtures/hosts/system.txt`** — Parrot stock, no user or tgt entries.
Baseline that other fixtures build on.

```
127.0.0.1	localhost
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
127.0.1.1	parrot
```

**`fixtures/hosts/user_managed.txt`** — system + a user's own entries
(no tgt tags). Tests must never delete these.

```
127.0.0.1	localhost
::1		localhost ip6-localhost ip6-loopback
127.0.1.1	parrot
192.168.1.50	homelab.local nas.local
10.0.0.1	router
```

**`fixtures/hosts/single_target.txt`** — system + one tgt-tagged line.
Most basic happy-path fixture.

```
127.0.0.1	localhost
::1		localhost ip6-localhost ip6-loopback
127.0.1.1	parrot
10.10.11.5	forest.htb dc01.htb.local	# tgt:htb-forest:forest
```

**`fixtures/hosts/multi_target.txt`** — system + several tagged lines
in one scenario. Tests scenario-level operations.

```
127.0.0.1	localhost
::1		localhost ip6-localhost ip6-loopback
127.0.1.1	parrot
172.16.10.20	web01.dante.local intranet.dante.local	# tgt:dante:web01
172.16.10.100	dc01.dante.local			# tgt:dante:dc01
172.16.5.5	jumpbox.dante.local			# tgt:dante:jumpbox
```

**`fixtures/hosts/multi_scenario.txt`** — system + entries from two
scenarios. Tests that scenario A's operations don't touch scenario B.

```
127.0.0.1	localhost
::1		localhost ip6-localhost ip6-loopback
127.0.1.1	parrot
172.16.10.20	web01.dante.local		# tgt:dante:web01
172.16.10.100	dc01.dante.local		# tgt:dante:dc01
10.20.30.5	api.acme.test			# tgt:customer-acme:api-gateway
10.20.30.6	web.acme.test			# tgt:customer-acme:webapp
```

**`fixtures/hosts/mixed.txt`** — the realistic case: system + user + tgt.
Tests that the user's hand-written entries survive every operation.

```
127.0.0.1	localhost
::1		localhost ip6-localhost ip6-loopback
127.0.1.1	parrot
192.168.1.50	homelab.local
10.10.11.5	forest.htb			# tgt:htb-forest:forest
10.0.0.1	router
172.16.10.20	web01.dante.local		# tgt:dante:web01
```

### `/etc/krb5.conf` fixtures

**`fixtures/krb5/empty.conf`** — bare `[libdefaults]`, no realms.

```
[libdefaults]
	default_realm = ATHENA.MIT.EDU
```

**`fixtures/krb5/one_realm.conf`** — one tgt-managed realm.

```
[libdefaults]
	default_realm = HTB.LOCAL

[realms]
    HTB.LOCAL = {
        kdc = DC01.HTB.LOCAL
    }
```

**`fixtures/krb5/two_realms.conf`** — two realms; tests that removing
one leaves the other intact.

```
[libdefaults]
	default_realm = DANTE.LOCAL

[realms]
    DANTE.LOCAL = {
        kdc = DC01.DANTE.LOCAL
    }
    OTHER.LOCAL = {
        kdc = DC01.OTHER.LOCAL
    }
```

**`fixtures/krb5/with_user_realm.conf`** — has a non-tgt-managed realm
the user added themselves. Tests must not touch it.

```
[libdefaults]
	default_realm = HTB.LOCAL

[realms]
    HTB.LOCAL = {
        kdc = DC01.HTB.LOCAL
    }
    CORP.EXAMPLE.COM = {
        kdc = kdc.corp.example.com
        admin_server = kdc.corp.example.com
    }
```

(This last one is the trickiest — distinguishing tgt-managed realms
from user realms in krb5.conf needs the same tagging treatment as
`/etc/hosts`. Open question below.)

### Fixture loading helper

```fish
# test/helpers.fish
function _test_load_fixture --argument-names target_var fixture_path
    set -l fixtures_dir (status dirname)/fixtures
    cat $fixtures_dir/$fixture_path > $$target_var
end
```

Use:
```fish
_test_setup_tmp
_test_load_fixture TGT_HOSTS_FILE hosts/multi_scenario.txt
```

### When you need a new fixture

Add a new file in `fixtures/<file>/`, name it after the *state* it
represents (not the test that uses it — fixtures should be reusable).
If you find yourself writing a one-off fixture inline in a test, that's
fine for unique edge cases — just don't copy-paste the same setup three
times.

### When fixtures *do* break

Format additions (e.g., we add a new tag schema) require touching every
fixture using the old schema. That's the cost of hand-written. Mitigation:
keep fixtures small (5–10 lines each) and consistent in shape so the
diff is mechanical.

## Open questions

1. Should the test suite require root for any test? Strong preference:
   no, ever. The whole `_tgt_hosts_write` test-mode branch exists to
   avoid sudo prompts during tests.
2. **Tagging tgt-managed krb5 realms**: `/etc/krb5.conf` has no
   line-comment-tag affordance like `/etc/hosts` does — realms are
   multi-line blocks. Options:
   (a) preceding comment line `# tgt:<scenario>:<realm>` immediately
   above each managed realm block;
   (b) a separate `[realms]`-style section we own entirely, e.g.
   `# >>> tgt managed >>>` ... `# <<< tgt managed <<<` markers around
   the whole tgt section, leaving user realms outside.
   Lean toward (b) — single block to add/remove, no per-realm comment
   parsing. Worth its own short spec? Probably yes if we actually
   tackle this in v1.

## Out of scope

- Property-based / fuzz testing. Overkill for this size of code.
- Snapshot testing. Overkill, and the fixtures already serve as snapshots.
- Performance benchmarks. The whole tool is sub-second; no point.
