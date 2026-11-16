#!/usr/bin/env python3
"""Start the game with its remote API, and call the API from a shell.

A program such as an LLM agent plays the game with these commands:

  tools/remote_game.py start                 start a headless game, print its URL
  tools/remote_game.py start --window        start the game in a window, for screenshots
  tools/remote_game.py eval 'city.info()'    run JavaScript in the game, print the JSON answer
  tools/remote_game.py eval - < script.js    run a script from standard input
  tools/remote_game.py state                 print game.state()
  tools/remote_game.py city-data --cell 40 40
                                             print each value of one tile as JSON
  tools/remote_game.py city-data --area 40 40 8 8 --fields structure,zone
                                             print the tiles of an area; without --area the whole city
  tools/remote_game.py screenshot out.png    save an image of the game window
  tools/remote_game.py city-image out.png --area 40 40 12 12
                                             save an image of some tiles; a headless game can do this
  tools/remote_game.py control-image out.png --scale 8
                                             save the picture of a drawn control, such as the SCURK canvas
  tools/remote_game.py guide                 print how to play through the API
  tools/remote_game.py types                 print the TypeScript declarations of the API
  tools/remote_game.py stop                  close the game

`start` uses a disposable profile and the packs in ext/, so the settings and
cities of the player do not change. `--profile player` uses the normal profile.
The game plays no sound. See docs/remote-api.md.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

import validate_project

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PORT = 9240
READY_LINE = 'The remote API listens on'
FAILED_LINE = 'The remote API cannot start'
START_TIMEOUT = 120
# the packs that a disposable profile uses: environment variable -> folder in ext/
PACKS = {'OPENSC2K_GRAPHICS_PACK': 'graphics', 'OPENSC2K_DATA_PACK': 'data'}


def session_folder(port):
    return Path(tempfile.gettempdir()) / f'opensc2k-remote-{port}'


def request(port, path, body=None, timeout=660):
    """Send one request to the game. Return (status, content type, bytes)."""
    message = urllib.request.Request(f'http://127.0.0.1:{port}{path}', data=body,
                                     method='POST' if body is not None else 'GET')
    if body is not None:
        message.add_header('Content-Type', 'text/plain; charset=utf-8')
    try:
        with urllib.request.urlopen(message, timeout=timeout) as answer:
            return answer.status, answer.headers.get('Content-Type', ''), answer.read()
    except urllib.error.HTTPError as error:
        return error.code, error.headers.get('Content-Type', ''), error.read()


def is_running(port):
    try:
        return request(port, '/', timeout=2)[0] == 200
    except OSError:
        return False


def start(args):
    if is_running(args.port):
        print(f'A game already listens on http://127.0.0.1:{args.port}')
        return 0
    folder = session_folder(args.port)
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    environment = dict(os.environ, GODOT_AUDIO_DRIVER='Dummy')
    session = {'port': args.port, 'user': ''}
    project_path = ROOT / 'game'
    if args.profile == 'disposable':
        project = validate_project.Project(folder)
        project.configure('remote')
        project_path = project.path
        session['user'] = str(project.user)
        for variable, name in PACKS.items():
            if (ROOT / 'ext' / name / 'pack.json').is_file():
                environment.setdefault(variable, str(ROOT / 'ext' / name))
    command = [args.godot, '--audio-driver', 'Dummy', '--path', str(project_path)]
    if not args.window:
        command.append('--headless')
    command += ['--', f'--api={args.port}']
    log = folder / 'game.log'
    with log.open('w') as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, env=environment,
                                   start_new_session=True)
    session['pid'] = process.pid
    (folder / 'session.json').write_text(json.dumps(session))
    deadline = time.monotonic() + START_TIMEOUT
    while time.monotonic() < deadline:
        output = log.read_text(errors='replace')
        if process.poll() is not None or FAILED_LINE in output:
            if process.poll() is None:
                process.terminate()
            print(f'The game did not start its remote API. Its output:\n{output}', file=sys.stderr)
            remove_session(folder, session)
            return 1
        if READY_LINE in output and is_running(args.port):
            if args.window:
                # a person watches: the view moves to the tiles that scripts change
                request(args.port, '/eval', b'view.follow = true', timeout=10)
            print(f'http://127.0.0.1:{args.port}')
            return 0
        time.sleep(0.2)
    process.terminate()
    print(f'The game did not open its port in {START_TIMEOUT} seconds. Its output:\n{log.read_text(errors="replace")}',
          file=sys.stderr)
    remove_session(folder, session)
    return 1


def remove_session(folder, session):
    """Remove the disposable profile and the files of a session."""
    if session.get('user'):
        shutil.rmtree(session['user'], ignore_errors=True)
    shutil.rmtree(folder, ignore_errors=True)


def process_runs(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def stop(args):
    folder = session_folder(args.port)
    session = json.loads((folder / 'session.json').read_text()) if (folder / 'session.json').is_file() else {}
    if is_running(args.port):
        request(args.port, '/eval', b'game.quit({ discard: true })', timeout=10)
    pid = session.get('pid')
    deadline = time.monotonic() + 15
    while pid and process_runs(pid) and time.monotonic() < deadline:
        time.sleep(0.2)
    if pid and process_runs(pid):
        os.kill(pid, 15)
    remove_session(folder, session)
    print('The game stopped.')
    return 0


def show(port, path, body=None):
    """Print the answer of a text route. Return the exit status."""
    try:
        status, content_type, content = request(port, path, body)
    except OSError as error:
        print(f'No game answers on port {port}: {error}. Run: tools/remote_game.py start', file=sys.stderr)
        return 2
    text = content.decode('utf-8', errors='replace')
    print(text)
    if status != 200:
        return 1
    if content_type.startswith('application/json'):
        try:
            return 0 if json.loads(text).get('ok', True) else 1
        except ValueError:
            return 1
    return 0


def evaluate(args):
    source = sys.stdin.read() if args.source == '-' else args.source
    return show(args.port, f'/eval?timeout={args.timeout}', source.encode('utf-8'))


def screenshot(args):
    return save_image(args, f'/screenshot?scale={args.scale}')


def save_image(args, route):
    """Save the image of a route to args.path. Return the exit status."""
    try:
        status, _, content = request(args.port, route)
    except OSError as error:
        print(f'No game answers on port {args.port}: {error}', file=sys.stderr)
        return 2
    if status != 200:
        print(content.decode('utf-8', errors='replace'), file=sys.stderr)
        return 1
    path = Path(args.path).resolve()
    path.write_bytes(content)
    print(path)
    return 0


def city_image(args):
    query = [f'size={args.size}', f'view={args.view}']
    if args.area:
        query += [f'{name}={value}' for name, value in zip(('x', 'y', 'width', 'height'), args.area)]
    return save_image(args, '/city-image?' + '&'.join(query))


def city_data(args):
    query = {}
    if args.cell:
        query.update(zip(('x', 'y'), args.cell))
    elif args.area:
        query.update(zip(('x', 'y', 'width', 'height'), args.area))
    for name in ('fields', 'format'):
        if getattr(args, name):
            query[name] = getattr(args, name)
    if args.empty:
        query['empty'] = 'true'
    return show(args.port, '/city-data' + ('?' + urllib.parse.urlencode(query) if query else ''))


def control_image(args):
    return save_image(args, '/control-image?' + urllib.parse.urlencode({'target': args.target, 'scale': args.scale}))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--port', type=int, default=int(os.environ.get('OPENSC2K_API_PORT', DEFAULT_PORT)))
    commands = parser.add_subparsers(dest='command', required=True)
    starter = commands.add_parser('start', help='Start the game with the remote API')
    starter.add_argument('--window', action='store_true', help='Show the game window; a headless game has no image')
    starter.add_argument('--profile', choices=('disposable', 'player'), default='disposable')
    starter.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    evaluator = commands.add_parser('eval', help='Run JavaScript in the game')
    evaluator.add_argument('source', help='The source, or - to read it from standard input')
    evaluator.add_argument('--timeout', type=int, default=30000, help='Milliseconds to wait for a promise')
    commands.add_parser('state', help='Print game.state()')
    shooter = commands.add_parser('screenshot', help='Save an image of the game window')
    shooter.add_argument('path')
    shooter.add_argument('--scale', type=float, default=1.0)
    drawer = commands.add_parser('city-image', help='Save an image of the city, or of some of its tiles')
    drawer.add_argument('path')
    drawer.add_argument('--area', type=int, nargs=4, metavar=('X', 'Y', 'WIDTH', 'HEIGHT'),
                        help='Draw only these tiles. The default is the whole city')
    drawer.add_argument('--size', choices=('small', 'medium', 'large'), default='small', help='The size of the tiles')
    drawer.add_argument('--view', default='city', help='city or underground')
    reader = commands.add_parser('city-data', help='Print the city, an area of it or one tile as JSON')
    reader.add_argument('--cell', type=int, nargs=2, metavar=('X', 'Y'), help='Each value of this tile')
    reader.add_argument('--area', type=int, nargs=4, metavar=('X', 'Y', 'WIDTH', 'HEIGHT'),
                        help='The tiles of this area. The default is the whole city')
    reader.add_argument('--fields', default='', help='The values to print, with commas: structure,zone,powered')
    reader.add_argument('--format', choices=('cells', 'columns'), default='', help='One object for each tile, or one array for each value')
    reader.add_argument('--empty', action='store_true', help='Also print the empty values of each tile')
    painter = commands.add_parser('control-image', help='Save the picture of a control that draws its content')
    painter.add_argument('path')
    painter.add_argument('--target', default='', help='The id or the name of the control. The default is the first one')
    painter.add_argument('--scale', type=int, default=1, help='From 1 to 16: the width of each picture pixel')
    commands.add_parser('guide', help='Print how to play through the API')
    commands.add_parser('types', help='Print the TypeScript declarations of the API')
    commands.add_parser('stop', help='Close the game')
    args = parser.parse_args()
    if args.command == 'start':
        return start(args)
    if args.command == 'stop':
        return stop(args)
    if args.command == 'eval':
        return evaluate(args)
    if args.command == 'screenshot':
        return screenshot(args)
    if args.command == 'city-image':
        return city_image(args)
    if args.command == 'city-data':
        return city_data(args)
    if args.command == 'control-image':
        return control_image(args)
    return show(args.port, '/' + args.command)


if __name__ == '__main__':
    sys.exit(main())
