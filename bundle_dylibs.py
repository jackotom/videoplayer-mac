#!/usr/bin/env python3
"""把 FFmpeg 及其依赖动态库打包进 app bundle，改用 @rpath，实现独立分发。

用法: bundle_dylibs.py <app二进制路径> <Frameworks目录>
"""
import os
import subprocess
import sys
import shutil


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def realpath(p):
    return os.path.realpath(p)


def install_name(path):
    """返回 dylib 的 LC_ID_DYLIB（完整 opt 路径）"""
    lines = [l.strip() for l in run(["otool", "-D", path]).splitlines() if l.strip()]
    return lines[1] if len(lines) > 1 else None


def homebrew_deps(path, skip_id=True):
    """返回该二进制引用的所有 /opt/homebrew 依赖（原始 install name 路径）。"""
    out = run(["otool", "-L", path]).splitlines()
    # out[0] 是 "path:"，dylib 的 out[1] 是它自己的 id，之后才是真实依赖
    deps = []
    for line in out[1:]:
        line = line.strip()
        if line.startswith("/opt/homebrew/"):
            deps.append(line.split("(")[0].strip())
    return deps


def main():
    app_binary = sys.argv[1]
    frameworks = sys.argv[2]
    os.makedirs(frameworks, exist_ok=True)

    # 1. 收集全部依赖：realpath -> install_name(opt 路径)
    seeds = [realpath(f"/opt/homebrew/lib/lib{l}.dylib")
             for l in ["avcodec", "avformat", "avutil", "swscale", "swresample"]]
    info = {}  # realpath -> opt install name
    seen = set()
    queue = list(seeds)
    while queue:
        f = realpath(queue.pop(0))
        if f in seen:
            continue
        seen.add(f)
        idn = install_name(f)
        if not idn:
            continue
        info[f] = idn
        for d in homebrew_deps(f):
            r = realpath(d)
            if r not in seen:
                queue.append(r)

    print(f"[bundle] 收集到 {len(info)} 个动态库")

    # 2. 拷贝 + 改 id + 改依赖
    for f, idn in sorted(info.items()):
        base = os.path.basename(idn)
        dst = os.path.join(frameworks, base)
        shutil.copy2(f, dst)
        os.chmod(dst, 0o755)
        subprocess.run(["install_name_tool", "-id", f"@rpath/{base}", dst], check=True)
        for dep in homebrew_deps(f):
            depbase = os.path.basename(dep)
            subprocess.run(["install_name_tool", "-change", dep, f"@rpath/{depbase}", dst], check=True)
        print(f"  ✓ {base}")

    # 3. 改 app 二进制
    for dep in homebrew_deps(app_binary, skip_id=False):
        depbase = os.path.basename(dep)
        subprocess.run(["install_name_tool", "-change", dep, f"@rpath/{depbase}", app_binary], check=True)
        print(f"  ✓ app: {depbase}")
    subprocess.run(["install_name_tool", "-add_rpath", "@executable_path/../Frameworks", app_binary], check=True)

    print("[bundle] 完成")


if __name__ == "__main__":
    main()
