"""Independent static checks for the patched original BAT strategies.

No Windows scripts, native programs or network requests are executed.
"""
from pathlib import Path
import argparse
import hashlib
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path('/workspace/zapret-original-rework/Zapret-1.10.4-reworked'))
    parser.add_argument('--original', type=Path, default=Path('/workspace/zapret-audit/zapret-discord-youtube-1.10.4'))
    parser.add_argument('--require-service-guard', action='store_true')
    args = parser.parse_args()
    root, original = args.root, args.original
    checks = 0

    def check(condition, message):
        nonlocal checks
        if not condition:
            raise AssertionError(message)
        checks += 1

    def hosts(filename):
        return [line.strip() for line in (root / 'lists' / filename).read_text(encoding='utf-8-sig').splitlines()
                if line.strip() and not line.lstrip().startswith('#')]

    def tokens(command):
        # These BAT commands quote whole values but contain no escaped quotes.
        return [item.replace('"', '') for item in re.findall(r'(?:[^\s"]+|"[^"]*")+', command)]

    def parse_strategy(path):
        data = path.read_bytes()
        check(b'\n' not in data.replace(b'\r\n', b''), path.name + ': Windows CRLF is retained')
        lines = data.decode('utf-8-sig').splitlines()
        invocation = [i for i, line in enumerate(lines) if line.startswith('"%BIN%winws.exe" ')]
        check(len(invocation) == 1, path.name + ': exactly one foreground native invocation')
        first = invocation[0]
        check(not any(re.match(r'(?i)^\s*start\s', line) for line in lines), path.name + ': no detached start invocation')
        check(lines[-1].startswith('--filter-udp=') and not lines[-1].endswith('^'), path.name + ': final native argument line remains at EOF')
        for index, line in enumerate(lines[first:], first + 1):
            if index != len(lines):
                check(line.endswith(' ^'), f'{path.name}:{index}: native continuation caret is present at physical EOL')
            check(not re.search(r'\^\s+$', line), f'{path.name}:{index}: no whitespace after caret')
        command = ' '.join(line[:-1].rstrip() if line.endswith('^') else line for line in lines[first:])
        short_root = 'C:\\Zapret\\Zapret-1.10.4-reworked\\'
        expanded = command.replace('%BIN%', short_root + 'bin\\').replace('%LISTS%', short_root + 'lists\\')
        expanded = expanded.replace('%GameFilterTCP%', '12').replace('%GameFilterUDP%', '12')
        check(len(expanded) < 8191, path.name + ': default native command fits CMD limit at the recommended short extraction path')
        parsed = tokens(command)
        check(parsed[0] == '%BIN%winws.exe', path.name + ': quoted binary path is first token')
        groups = [[]]
        for item in parsed[1:]:
            if item == '--new':
                groups.append([])
            else:
                groups[-1].append(item)
        check(all(groups), path.name + ': no empty profile group')
        return lines, first, groups

    expected_yt = {
        'youtube.com', 'youtu.be', 'youtube-nocookie.com', 'youtubekids.com',
        'googlevideo.com', 'ytimg.com', 'ytimg.l.google.com', 'yt3.ggpht.com',
        'yt4.ggpht.com', 'yt3.googleusercontent.com', 'youtubei.googleapis.com',
        'youtube.googleapis.com', 'youtubeembeddedplayer.googleapis.com',
        'jnn-pa.googleapis.com', 'wide-youtube.l.google.com', 'youtube-ui.l.google.com',
        'yt-video-upload.l.google.com',
    }
    expected_oa = {'chatgpt.com', 'openai.com', 'oaistatic.com', 'oaiusercontent.com', 'challenges.cloudflare.com'}
    expected_tg = {'telegram.org', 't.me', 'telegram.me', 'telegram-cdn.org'}
    for filename, expected in [('list-youtube.txt', expected_yt), ('list-openai.txt', expected_oa), ('list-telegram.txt', expected_tg)]:
        names = hosts(filename)
        check(len(names) == len(expected) and set(names) == expected, filename + ': exact scoped host set with no duplicates')
        check(all(re.fullmatch(r'[a-z0-9][a-z0-9.-]*\.[a-z]{2,}', name) for name in names), filename + ': plain domain syntax')

    native = [p for p in (original / 'bin').rglob('*') if p.is_file()]
    check(len(native) == 27, 'reference has exactly 27 original native/helper files')
    for path in native:
        rel = path.relative_to(original)
        check((root / rel).is_file() and hashlib.sha256((root / rel).read_bytes()).digest() == hashlib.sha256(path.read_bytes()).digest(), str(rel) + ': original bytes retained')
    print('PASS: exact 17/5/4 added domain sets and all 27 original bin files are unchanged')

    strategies = sorted(root.glob('general*.bat'))
    check(len(strategies) == 22, 'all 22 original strategy files remain')
    check({p.name for p in strategies} == {p.name for p in original.glob('general*.bat')}, 'strategy filenames preserved')
    excludes = {
        '--hostlist-exclude=%LISTS%list-exclude.txt',
        '--hostlist-exclude=%LISTS%list-exclude-user.txt',
        '--ipset-exclude=%LISTS%ipset-exclude.txt',
        '--ipset-exclude=%LISTS%ipset-exclude-user.txt',
    }
    groups_by_name = {}
    for path in strategies:
        lines, invocation, groups = parse_strategy(path)
        groups_by_name[path.name] = groups
        body = '\n'.join(lines)
        check(lines[1] == 'setlocal DisableDelayedExpansion', path.name + ': delayed expansion disabled before paths are used')
        check('cd /d "%~dp0" || exit /b 1' in lines and 'cd /d "%BIN%" || exit /b 1' in lines, path.name + ': both directory changes quoted and checked')
        check('call service.bat' not in body and 'check_updates' not in body, path.name + ': no relative service calls or automatic update request')
        for command in ['status_zapret', 'load_game_filter', 'load_user_lists']:
            check('call "%~dp0service.bat" ' + command in lines, path.name + ': absolute quoted service call ' + command)
        check(re.search(r'call "%~dp0service\.bat" status_zapret\nif errorlevel 1 \(\n\s+pause\n\s+exit /b 1\n\)', body) is not None, path.name + ': a failed preflight prevents launch')
        quic = groups[0]
        for name in ['list-general.txt', 'list-general-user.txt', 'list-youtube.txt', 'list-openai.txt', 'list-telegram.txt']:
            check('--hostlist=%LISTS%' + name in quic, path.name + ': first QUIC group includes ' + name)
        check(excludes <= set(quic), path.name + ': first QUIC group keeps all four exclusions')
        google = [g for g in groups if '--hostlist=%LISTS%list-google.txt' in g]
        if path.name == 'general (ALT5).bat':
            check(not google, path.name + ': no invented Google group in intentionally disabled original ALT5')
            first_effective = [line.strip() for line in lines[:invocation] if line.strip() and not line.startswith(('echo ', '::', '@echo', 'setlocal', 'pause'))]
            check(first_effective[0] == 'exit /b 1', 'ALT5 stops unconditionally before cd/service/native commands')
            check(body.index('exit /b 1') < body.index('call "%~dp0service.bat"'), 'ALT5 guard precedes service side effects')
        else:
            check(len(groups) == 10, path.name + ': 9 original groups plus isolated Telegram Web group')
            check(len(google) == 1 and '--filter-tcp=443' in google[0], path.name + ': exactly one Google TCP443 group')
            check('--hostlist=%LISTS%list-openai.txt' in google[0] and excludes <= set(google[0]), path.name + ': Google/OpenAI group honors all four exclusions')
            telegram = [g for g in groups if '--hostlist=%LISTS%list-telegram.txt' in g and '--filter-tcp=443' in g]
            check(len(telegram) == 1, path.name + ': exactly one separate Telegram TCP443 group')
            expected_tg_args = {
                '--filter-tcp=443', '--hostlist=%LISTS%list-telegram.txt', '--ip-id=zero',
                '--dpi-desync=multisplit', '--dpi-desync-split-seqovl=681', '--dpi-desync-split-pos=1',
                '--dpi-desync-split-seqovl-pattern=%BIN%tls_clienthello_www_google_com.bin',
            } | excludes
            check(set(telegram[0]) == expected_tg_args and len(telegram[0]) == len(expected_tg_args), path.name + ': isolated Telegram rule uses exact previously successful BASE681/Google flags')

        # Resolve only file-valued %BIN%/%LISTS% references. We model expansion with
        # difficult path characters without invoking CMD or claiming Windows coverage.
        for reference in re.findall(r'"(%(?:BIN|LISTS)%[^"\r\n]+)"', body):
            prefix = '%BIN%' if reference.startswith('%BIN%') else '%LISTS%'
            relative = ('bin/' if prefix == '%BIN%' else 'lists/') + reference[len(prefix):].replace('\\', '/')
            check((root / relative).is_file(), path.name + ': referenced file exists: ' + relative)
            fake_base = 'C:\\Проверка папки @ & tools\\Zapret\\'
            expanded = fake_base + relative.replace('/', '\\')
            parsed_path = tokens('"' + expanded + '"')
            check(parsed_path == [expanded], path.name + ': quoted reference remains a single logical token for spaces/Unicode/@/&')
        check((root / 'service.bat').is_file(), path.name + ': referenced service file exists')

    main_google = next(g for g in groups_by_name['general.bat'] if '--hostlist=%LISTS%list-google.txt' in g)
    actual_flags = [arg for arg in main_google if arg.startswith('--dpi-desync') or arg.startswith('--ip-id=')]
    expected_flags = [
        '--ip-id=zero', '--dpi-desync=fake,fakedsplit', '--dpi-desync-split-pos=1',
        '--dpi-desync-fooling=badseq', '--dpi-desync-badseq-increment=2', '--dpi-desync-repeats=8',
        '--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com',
    ]
    check(actual_flags == expected_flags, 'main Google/OpenAI rule exactly retains user-proven FAKE TLS AUTO ALT flags and order')
    main_general = next(g for g in groups_by_name['general.bat'] if '--filter-tcp=80,443' in g and '--hostlist=%LISTS%list-general.txt' in g)
    check('--dpi-desync-split-seqovl=568' in main_general and '--dpi-desync-split-seqovl-pattern=%BIN%tls_clienthello_4pda_to.bin' in main_general, 'original distinct general BASE568/4pda rule was not confused with Telegram BASE681/Google')
    exp_discord = [g for g in groups_by_name['general (EXP).bat'] if '--filter-udp=19294-19344,50000-50100' in g]
    check(len(exp_discord) == 1, 'EXP retains one Discord UDP port group')
    check('--filter-l7=discord,stun' in exp_discord[0] and not any('unknown' in token or token.startswith('--dpi-desync-any-protocol=') for token in exp_discord[0]), 'EXP Discord UDP no longer captures unknown protocols')
    print('PASS: all 22 BAT bodies, file references, foreground/EOF form, exclusions, disabled ALT5 and scoped EXP pass static checks')

    default_ipset = [line.strip() for line in (root / 'lists/ipset-all.txt').read_text().splitlines() if line.strip()]
    check(default_ipset == ['203.0.113.113/32'], 'default IPSet remains documentation-only sentinel, not empty/ANY')
    check(not (root / 'utils/game_filter.enabled').exists(), 'Game Filter is not enabled in the package')
    service = (root / 'service.bat').read_text(encoding='utf-8-sig')
    for variable in ['GameFilterTCP', 'GameFilterUDP']:
        check('set "' + variable + '=12"' in service, 'disabled default retains dummy port12 for ' + variable)
    new_hosts = expected_yt | expected_oa | expected_tg
    def matches(name):
        return any(name == suffix or name.endswith('.' + suffix) for suffix in new_hosts)
    for name in ['ya.ru', 'yandex.ru', 'vk.com', 'gosuslugi.ru', 'sberbank.ru', 'ozon.ru',
                 'store.steampowered.com', 'steamcommunity.com', 'cloudflare.com',
                 'example.cloudflare.com', 'chatgpt.com.evil.example', 'telegram.org.evil.example']:
        check(not matches(name), 'new service lists do not capture unrelated host: ' + name)
    print('PASS: default Game/IPSet filters remain narrow; representative Russian/Steam/unrelated hosts do not match the NEW service lists')

    # The service agent may still be editing the installer when this test first runs.
    installer_start = service.find('\n:service_install\n')
    installer_end = service.find('\n:service_remove\n', installer_start + 1)
    installer = service[installer_start:installer_end if installer_end != -1 else None]
    alt5_lines = [line for line in installer.splitlines() if 'ALT5' in line]
    if not alt5_lines and args.require_service_guard:
        check(False, 'final service installer has no ALT5 rejection guard')
    if alt5_lines:
        check(any('if' in line.lower() and ('neq' in line.lower() or 'not' in line.lower() or 'skip' in line.lower() or 'disabled' in line.lower() or 'goto' in line.lower()) for line in alt5_lines), 'service installer explicitly filters/rejects ALT5')
        print('PASS: service installer includes an explicit ALT5 exclusion guard')
    else:
        print('PENDING: service installer ALT5 guard; rerun --require-service-guard after service patch is ready')
    print(f'PASS: {checks} independent static assertions; no Windows execution, native process or real routing test performed.')


if __name__ == '__main__':
    main()
