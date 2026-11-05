"""Read module declarations and plan a build without touching its source tree."""
from collections import Counter
import heapq
import json
import re


class BuildError(Exception):
    pass


RAILS_HOOKS = {
    "user_settings": "UserSettingsExtensions",
    "status_source": "StatusSourceExtensions",
}

ID = re.compile(r"[a-z][a-z0-9_]*")
KEYS = {"Depends", "Hook", "File", "Replace", "Watch", "Schema", "Field", "Assets", "Style", "Theme", "Locale", "Register"}


def relative(value):
    if not value or "\\" in value or any(part in ("", ".", "..") for part in value.split("/")):
        raise BuildError(f"Invalid relative path: {value!r}")
    return value


def plain(root, name):
    path = root
    for part in relative(name).split("/"):
        path = path / part
        if path.is_symlink():
            raise BuildError(f"Unexpected symbolic link: {path}")
    return path


def manifest(path):
    values = {key: [] for key in KEYS}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, separator, value = line.partition(": ")
        if not separator or key not in KEYS or not value or value in values[key]:
            raise BuildError(f"Invalid or duplicate declaration in {path}:{number}: {line}")
        values[key].append(value)
    return values


def selection(root, lines):
    names = [line.partition("#")[0].strip() for line in lines]
    counts = Counter(name for name in names if name)
    errors = [f"Duplicate module: {name}" for name in counts if counts[name] > 1]
    known = {p.parent.name: p for p in (root / "modules").glob("*/module.conf")
             if p.parent.name != "loader" and ID.fullmatch(p.parent.name)}
    modules = {}

    def visit(name, chain):
        if name in chain:
            errors.append("Dependency cycle: " + " -> ".join([*chain, name]))
            return
        if name not in known:
            errors.append("Unknown module: " + " -> ".join([*chain, name]))
            return
        if name not in modules:
            modules[name] = manifest(plain(root, f"modules/{name}/module.conf"))
        for dep in modules[name]["Depends"]:
            if dep not in counts:
                errors.append(f"{name}: Depends: {dep} (not selected; {' -> '.join([*chain, name, dep])})")
            visit(dep, [*chain, name])

    for name in sorted(counts):
        visit(name, [])
    if errors:
        raise BuildError("Invalid module selection:\n  " + "\n  ".join(dict.fromkeys(errors))
                         + "\nEdit the module list in build.sh and retry.")
    pending = {n: set(conf["Depends"]) for n, conf in modules.items()}
    ready = [n for n, deps in pending.items() if not deps]
    heapq.heapify(ready)
    ordered = {}
    while ready:
        name = heapq.heappop(ready)
        ordered[name] = modules[name]
        for other, deps in pending.items():
            if name in deps:
                deps.remove(name)
                if not deps:
                    heapq.heappush(ready, other)
    return ordered


def concern_file(owner, symbol, declared):
    if not re.fullmatch(r"Wxw::[A-Z][A-Za-z0-9]*", symbol):
        raise BuildError(f"{owner}: Invalid concern name: {symbol}")
    basename = re.sub(r"(?<!^)(?=[A-Z])", "_", symbol.removeprefix("Wxw::")).lower()
    if f"app/models/concerns/wxw/{basename}.rb" not in declared:
        raise BuildError(f"{owner}: Missing implementation for {symbol}")


def patch_paths(patch):
    headers = re.findall(r"^--- ([^\n]+)\n\+\+\+ ([^\n]+)$", patch.read_text(), re.M)
    if not headers:
        raise BuildError(f"No unified diff in {patch}")
    paths = set()
    for old, new in headers:
        if not old.startswith("a/") or new != "b/" + old[2:]:
            raise BuildError(f"Expected an existing upstream file in {patch}: {old} / {new}")
        paths.add(relative(old[2:]))
    return paths


class Plan:
    def __init__(self, root, selected):
        self.patches = {}
        self.targets = {}
        self.files = {}
        self.schemas = []
        self.fields = {}
        self.assets = []
        self.styles = []
        self.themes = []
        self.locales = {}
        self.registered = {}
        self.patched = set()
        for owner, conf in {"loader": manifest(root / "loader/base.conf"), **selected}.items():
            base = root / ("loader" if owner == "loader" else f"modules/{owner}")
            for hook in conf["Hook"]:
                self.hook(root, hook, owner)
            for name in conf["Watch"]:
                self.target(relative(name), owner, "text-lf")
            overlay = plain(base, "overlay")
            declared = set(conf["File"] + conf["Replace"])
            actual = {p.relative_to(overlay).as_posix() for p in overlay.rglob("*")
                      if p.is_file() or p.is_symlink()}
            if declared != actual:
                raise BuildError(f"{owner}: Overlay file list differs: {sorted(declared ^ actual)}")
            for name in sorted(declared):
                if name in conf["Replace"]:
                    self.target(name, owner, "raw")
                self.add(name, plain(overlay, name), owner)
            for name in conf["Schema"]:
                self.schemas.append(plain(base, name).read_text().strip("\n"))
            for value in conf["Field"]:
                field, _, symbol = value.partition(" ")
                if "status_settings" not in selected or not ID.fullmatch(field) or field in self.fields:
                    raise BuildError(f"{owner}: Invalid or duplicate status field: {value}")
                concern_file(owner, symbol, declared)
                self.fields[field] = symbol
            for lang in conf["Locale"]:
                if not re.fullmatch(r"[a-z]{2,3}(?:-[a-zA-Z0-9]+)*", lang):
                    raise BuildError(f"{owner}: Invalid locale: {lang}")
                name = f"app/javascript/mastodon/locales/{lang}.json"
                self.target(name, owner, "text-lf")
                data = json.loads(plain(base, f"locales/{lang}.json").read_text())
                messages = self.locales.setdefault(name, {})
                if not isinstance(data, dict) or not all(isinstance(v, str) for v in data.values()):
                    raise BuildError(f"{owner}: Expected locale messages in {lang}.json")
                if messages.keys() & data.keys():
                    raise BuildError(f"{owner}: Duplicate locale keys: {sorted(messages.keys() & data.keys())}")
                messages.update(data)
            for registration in conf["Register"]:
                hook, _, concern = registration.partition(" ")
                if hook not in RAILS_HOOKS:
                    raise BuildError(f"{owner}: Invalid Rails registration: {registration}")
                concern_file(owner, concern, declared)
                self.hook(root, f"rails/{hook}", owner)
                concerns = self.registered.setdefault(hook, [])
                if concern in concerns:
                    raise BuildError(f"{owner}: Duplicate Rails registration: {registration}")
                concerns.append(concern)
            for theme in conf["Theme"]:
                if not re.fullmatch(r"[a-z][a-z0-9-]*", theme) or theme in self.themes:
                    raise BuildError(f"{owner}: Invalid or duplicate theme: {theme}")
                self.themes.append(theme)
                self.target("config/themes.yml", owner, "text-lf")
            for style in conf["Style"]:
                if not ID.fullmatch(style) or style in self.styles or f"app/javascript/styles/mastodon/{style}.scss" not in declared:
                    raise BuildError(f"{owner}: Invalid or missing component stylesheet: {style}")
                self.styles.append(style)
            for name in conf["Assets"]:
                script = plain(base, name)
                if not script.is_file():
                    raise BuildError(f"{owner}: Missing asset recipe: {name}")
                self.assets.append((owner, script))

    def hook(self, root, hook, owner):
        patch = plain(root / "loader/patches", hook + ".patch")
        self.patches[patch] = None
        paths = patch_paths(patch)
        self.patched.update(paths)
        for name in paths:
            self.target(name, owner, "text-lf")

    def target(self, name, owner, kind):
        expected, owners = self.targets.setdefault(name, (kind, set()))
        if kind != expected or (kind == "raw" and owners):
            raise BuildError(f"Conflicting upstream target: {name}")
        owners.add(owner)

    def add(self, name, source, owner):
        relative(name)
        if name in self.files:
            raise BuildError(f"{owner}: File already supplied by {self.files[name][1]}: {name}")
        self.files[name] = (source, owner)
