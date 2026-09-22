#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
current = root / "scripts/install-bfs-menu-current.sh"
source = current.resolve().read_text()

# Password policy: explicit installer floor must occur after blank-lock handling
# and before confirmation/chpasswd.
fn = source[source.index("prompt_optional_password() {"):source.index("\n}\n\nif [[ ! -f \"$STATE_DIR/accounts_configured\"", source.index("prompt_optional_password() {"))+3]
blank = fn.index('if [[ -z "$password_one" ]]')
floor = fn.index('(( ${#password_one} < 8 ))')
confirm = fn.index('Retype the password.')
backend = fn.index('| chpasswd')
assert blank < floor < confirm < backend
assert 'Password must be at least 8 characters.' in fn
assert 'unset password_one password_two' in fn
assert 'BAD PASSWORD' not in fn

for call in (
    'prompt_optional_password "$USERNAME_VALUE"',
    'prompt_optional_password "$user_name" "Standard user',
    'prompt_optional_password "$user_name" "System/service account',
    'prompt_optional_password root root',
):
    assert call in source, f"missing shared password policy caller: {call}"

# MD personality preload policy and 6.18 compatibility path.
for level, driver in (
    ("linear", "linear"), ("raid0", "raid0"), ("raid1", "raid1"),
    ("raid10", "raid10"), ("raid4", "raid456"),
    ("raid5", "raid456"), ("raid6", "raid456"),
):
    assert re.search(rf"{re.escape(level)}[^\n]*\)[^\n]*printf '%s' {re.escape(driver)}", source), level
assert 'cmdline_append_unique storage_cmdline "rd.driver.pre=$driver"' in source
assert 'expected="rd.driver.pre=$driver"' in source
assert 'rd.driver.pre=*' in source
assert 'configure_md_618_compat_policy || exit 1' in source
assert 'reason=md-v1.2-nonzero-reserved-padding' in source
assert 'md_mod.check_new_feature=0' in source
assert 'apply_md_618_compat_to_grub_config "$grub_tmp"' in source
assert 'vmlinuz-6\\.18\\.' in source

print("installer pre-RC policy regression: PASS")
