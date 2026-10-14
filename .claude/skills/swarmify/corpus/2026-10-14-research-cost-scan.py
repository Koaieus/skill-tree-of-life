import json, re, os, glob, sys
D = os.path.expanduser("~/.claude/projects/-home-bramh-skill-tree-of-life")
def txt(c):
    if isinstance(c, str): return c
    out = []
    if isinstance(c, list):
        for b in c:
            if isinstance(b, dict):
                if b.get("type") == "text": out.append(b.get("text", ""))
                elif b.get("type") == "tool_result": out.append(txt(b.get("content")))
    return "\n".join(out)
def rlen(c):
    return len(txt(c))
rows = []
for f in sorted(glob.glob(D + "/*.jsonl")):
    sid = os.path.basename(f)[:-6]
    first_prompt = None; first_ts = None; skill_hit = False
    uses = []   # ordered tool_use dicts
    results = {}  # id -> len
    order = {}  # id -> record idx
    cutoff = None; idx = 0
    total_result_chars = 0
    with open(f, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            idx += 1
            try: r = json.loads(line)
            except Exception: continue
            t = r.get("type"); m = r.get("message") or {}
            c = m.get("content")
            if t == "user":
                if first_prompt is None and r.get("timestamp"):
                    first_ts = r["timestamp"]
                if first_prompt is None and (isinstance(c, str) or isinstance(c, list)):
                    tt = txt(c)
                    if tt.strip() and "<command-name>" in tt or "/swarmify" in tt or tt.strip():
                        first_prompt = tt
                if isinstance(c, list):
                    for b in c:
                        if isinstance(b, dict) and b.get("type") == "tool_result":
                            n = rlen(b.get("content"))
                            results[b.get("tool_use_id")] = n
                            total_result_chars += n
            elif t == "assistant" and isinstance(c, list):
                for b in c:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        inp = b.get("input") or {}
                        name = b.get("name")
                        if name == "Skill" and inp.get("skill") == "swarmify": skill_hit = True
                        if b.get("id") not in order:
                            order[b.get("id")] = len(uses)
                            uses.append({"id": b.get("id"), "name": name, "input": inp})
                            if cutoff is None:
                                if name == "AskUserQuestion": cutoff = len(uses)-1
                                elif name == "Bash" and "gh issue comment" in (inp.get("command") or ""): cutoff = len(uses)-1
    if first_prompt is None: continue
    if "/swarmify" in first_prompt: skill_hit = True
    if not skill_hit: continue
    d = (first_ts or "")[:10]
    if not ("2026-09-14" <= d <= "2026-10-14"): continue
    # prompt issue numbers
    p = re.sub(r"\d{4}-\d{2}-\d{2}", "", first_prompt)
    nums = sorted(set(a or b for a, b in re.findall(r"#(\d{1,4})\b|(?<![\w.#])(\d{3,4})(?![\w.-])", p)))
    nums = [n for n in nums if int(n) >= 2 and not (len(n)<3 and not re.search("#"+n, p))]
    cut = cutoff if cutoff is not None else len(uses)
    res = {"sid": sid[:8], "date": d, "prompt_nums": nums, "cutoff_is": ("AskUser" if cutoff is not None and uses[cutoff]["name"]=="AskUserQuestion" else ("comment" if cutoff is not None else "none")),
           "total_chars": total_result_chars, "n_uses": len(uses)}
    ghv = {"n":0,"chars":0}; reads={"n":0,"whole":0,"ranged":0,"chars":0}; bashread={"n":0,"chars":0}
    agents=[]; rchars=0; rlist=[]
    for i,u in enumerate(uses[:cut]):
        rl = results.get(u["id"], 0); rchars += rl
        nm=u["name"]; inp=u["input"]
        if nm=="Bash":
            cmd = inp.get("command") or ""
            if re.search(r"gh issue (view|comment)|--comments", cmd) and "gh issue comment" not in cmd:
                ghv["n"]+=1; ghv["chars"]+=rl
            elif re.match(r"\s*(cat|sed -n|head|tail)\b", cmd) or re.search(r"\|\s*sed -n", cmd):
                bashread["n"]+=1; bashread["chars"]+=rl
        elif nm=="Read":
            reads["n"]+=1; reads["chars"]+=rl
            if "offset" in inp or "limit" in inp: reads["ranged"]+=1
            else: reads["whole"]+=1
            rlist.append(os.path.basename(inp.get("file_path","")))
        elif nm in ("Agent","Task"):
            st = inp.get("subagent_type")
            if st == "Explore":
                agents.append({"model": inp.get("model") or "none", "chars": rl})
    res.update(gh=ghv, read=reads, bashread=bashread, agents=agents, research_chars=rchars, reads_files=rlist)
    rows.append(res)
json.dump(rows, open(sys.argv[1],"w"), indent=1)
print(len(rows))
