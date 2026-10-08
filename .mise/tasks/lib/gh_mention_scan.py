"""Refuse a gh call whose posted text would ping someone — called by .mise/bin/gh.

Usage: python3 gh_mention_scan.py <stdin-file-or-empty> <gh args...>
Exit 0 = clean (or nothing posted); exit 64 = refused, the reason on stderr.

What counts as posted: the text behind --body/-b, --body-file/-F (a file, or `-`
for stdin), --title/-t, and `gh api` fields (-f/--raw-field, -F/--field, where
`key=@path` reads a file) plus --input. Reads (`gh issue view`) carry none of
these and are never scanned.

What is refused, once fenced blocks and inline code spans are stripped (GitHub
links no mention inside code, so `@export` in backticks is fine):
  - a bare `@name` — a live mention that notifies whoever owns that login;
  - a `#{name}` — a swarmify handle the clerk never resolved to a number.
The repo owner's own login is always allowed (owner, 2026-10-08: "my own name
should be free to mention"). GH_MENTION_OK=1 on the call is the escape hatch for
any other deliberate mention.
"""
import os
import re
import sys

_FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})[^\n]*\n.*?(?:^ {0,3}\1[^\n]*$|\Z)", re.M | re.S)
_SPAN = re.compile(r"(`+)(?!`).+?(?<!`)\1(?!`)", re.S)
# GitHub's own boundary: an `@` after a word char (mail@host) or `/` is no mention.
_MENTION = re.compile(r"(?<![\w/`@.])@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:/[\w.-]+)?")
_HANDLE = re.compile(r"#\{[\w-]+\}")
_ALLOWED = {"@koaieus"}  # lower-case; GitHub logins are case-insensitive
_TAKES_VALUE = {"--body", "-b", "--title", "-t", "--body-file", "-F", "--input",
	"-f", "--raw-field", "--field"}


def _read(path, stdin_file):
	if path == "-":
		path = stdin_file
	try:
		with open(path, encoding="utf-8", errors="replace") as f:
			return f.read()
	except OSError:
		return ""  # gh itself reports a missing file; not this scan's call


def posted_texts(args, stdin_file):
	is_api = bool(args) and args[0] == "api"
	out = []
	i = 0
	while i < len(args):
		a = args[i]
		i += 1
		key, eq, val = a.partition("=")
		if not (eq and key.startswith("--")):
			if a not in _TAKES_VALUE:
				continue
			key, val = a, (args[i] if i < len(args) else "")
			i += 1
		if key in ("--body", "-b") or (key in ("--title", "-t") and not is_api):
			out.append(val)
		elif key in ("--body-file", "--input") or (key == "-F" and not is_api):
			out.append(_read(val, stdin_file))
		elif key in ("-f", "--raw-field", "-F", "--field") and is_api:
			_, _, fv = val.partition("=")
			raw = key in ("-f", "--raw-field")
			out.append(_read(fv[1:], stdin_file) if fv.startswith("@") and not raw else fv)
	return out


def offences(text, strip_code=True):
	"""strip_code=False for text GitHub does not render as Markdown (commit messages)."""
	prose = _SPAN.sub("", _FENCE.sub("", text)) if strip_code else text.replace("`", " ")
	mentions = [m for m in _MENTION.findall(prose) if m.lower() not in _ALLOWED]
	return mentions, _HANDLE.findall(prose)


def main():
	stdin_file, args = sys.argv[1], sys.argv[2:]
	if os.environ.get("GH_MENTION_OK") == "1":
		return 0
	mentions, handles = [], []
	for text in posted_texts(args, stdin_file):
		m, h = offences(text)
		mentions += m
		handles += h
	if not (mentions or handles):
		return 0
	msg = ["gh shim: REFUSED — this call would post text to GitHub that it must not."]
	if mentions:
		msg.append(f"  live mention(s) outside code: {', '.join(sorted(set(mentions)))}")
		msg.append("  A bare @name notifies whoever owns that login — a stranger, as in #1383.")
		msg.append("  Godot annotations go in backticks (`@export`); a deliberate ping of a")
		msg.append("  collaborator is GH_MENTION_OK=1 on this one call.")
	if handles:
		msg.append(f"  unresolved swarmify handle(s): {', '.join(sorted(set(handles)))}")
		msg.append("  The clerk resolves #{name} to #<number>; one left over means its issue was")
		msg.append("  never declared in the manifest — file it or write the number.")
	msg.append("  Nothing was sent. Fix the text and re-run.")
	print("\n".join(msg), file=sys.stderr)
	return 64


if __name__ == "__main__":
	sys.exit(main())
