# Turn raw.json into kpis.json. Input: raw.json. Args: $targets (object), $now (epoch seconds).

def ts: fromdateiso8601;
def median: if length == 0 then null else sort as $s | ($s | length) as $n
  | if $n % 2 == 1 then $s[($n - 1) / 2] else ($s[$n / 2 - 1] + $s[$n / 2]) / 2 end end;
def hrs($a; $b): (($b | ts) - ($a | ts)) / 3600;
def r1: if . == null then null else ((. * 10) | round) / 10 end;
def r0: if . == null then null else round end;
def inw($a; $b): . != null and (ts >= $a) and (ts < $b);
def plural($n; $w): "\($n) \($w)\(if $n == 1 then "" else "s" end)";

# 90 minutes / 3.5 hours / 2.4 days
def fmt_h: if . == null then "–"
  elif . < 1 then "\((. * 60) | round) min"
  elif . < 48 then "\(r1) h"
  else "\((. / 24) | r1) days" end;
def fmt_d($h): ($h / 24 | r1);
def day: .[0:10];

def band($t; $v):   # -> green | amber | red | na
  if $v == null then "na"
  elif $t.better == "higher" then (if $v >= $t.green then "green" elif $v >= $t.amber then "amber" else "red" end)
  else (if $v <= $t.green then "green" elif $v <= $t.amber then "amber" else "red" end) end;

# Compare this period with the previous one. "better"/"worse"/"flat"/"n/a".
def trend($t; $cur; $prev):
  if $cur == null or $prev == null then {dir: "n/a", pct: null}
  elif $prev == 0 then (if $cur == 0 then {dir: "flat", pct: 0}
                        else {dir: (if ($t.better == "higher") == ($cur > 0) then "better" else "worse" end), pct: null} end)
  else (($cur - $prev) / $prev) as $p
    | {pct: ($p * 100 | r0),
       dir: (if ($p | fabs) < 0.1 then "flat"
             elif ($t.better == "higher") == ($p > 0) then "better" else "worse" end)} end;

# One period's numbers. $s/$e are epoch bounds of the period.
def period($s; $e; $days):
  (.prs   | map(select(.merged_at | inw($s; $e)))) as $prs
  | (.deploys | map(select(.at | inw($s; $e)))) as $dep
  | (.bugs | map(select(.closed_at | inw($s; $e)))) as $fixed
  | ($prs | map(select(.first_commit_at != null) | . + {lead: hrs(.first_commit_at; .merged_at)})) as $lead
  | ($prs | map(select(.first_review_at != null) | . + {wait: ([hrs(.created_at; .first_review_at), 0] | max)})) as $rev
  | {
      prs: $prs, dep: $dep, fixed: $fixed, lead: $lead, rev: $rev,
      deploys: ($dep | length),
      per_week: (($dep | length) / ($days / 7)),
      lead_median: ($lead | map(.lead) | median),
      wait_median: ($rev | map(.wait) | median),
      reverts: ($prs | map(select(.is_revert))),
      cfr: (if ($prs | length) == 0 then null else (100 * ($prs | map(select(.is_revert)) | length) / ($prs | length)) end),
      ttr_median: ($fixed | map(hrs(.created_at; .closed_at)) | median),
      unreviewed_pct: (if ($prs | map(select(.number != null)) | length) == 0 then null
                       else (100 * ($prs | map(select(.number != null and .first_review_at == null)) | length) / ($prs | map(select(.number != null)) | length)) end)
    };

# Eight weekly buckets, oldest first. The filter runs on {raw, s, e}.
def sparkline(f): . as $raw | [range(0; 8) as $i
  | {raw: $raw, s: ($now - (8 - $i) * 604800), e: ($now - (7 - $i) * 604800)} | f];

. as $raw
| $targets as $T
| ($raw.days) as $days
| ($now - $days * 86400) as $w0
| ($w0 - $days * 86400) as $p0
| ($raw | period($w0; $now + 1; $days)) as $cur
| ($raw | period($p0; $w0; $days)) as $prev
| ($raw.mode == "github") as $gh
| ($T.min_sample) as $minn

# ------------------------------------------------------------ 1. deployment frequency
| ($cur.dep | map(.at | ts) | sort) as $dts
| (if ($dts | length) < 2 then null
   else [range(1; $dts | length) as $i | {gap: ($dts[$i] - $dts[$i - 1]), from: $dts[$i - 1], to: $dts[$i]}] | max_by(.gap) end) as $gap
| ($cur.dep | map(select(.status == "failure")) | length) as $failed_deploys
| ($raw.deploy_source) as $dsrc
| {
    id: "deploy_frequency", name: "Deployment frequency", question: "How often do we ship?",
    value: ($cur.per_week | r1), unit: "per week", display: "\($cur.per_week | r1) / week",
    prev_value: ($prev.per_week | r1), prev_display: "\($prev.per_week | r1) / week",
    n: $cur.deploys, sample_label: "\(plural($cur.deploys; (if $dsrc == "merges" then "merge" elif $dsrc == "tags" then "tag" elif $dsrc == "releases" then "release" else "deploy" end)))",
    low_sample: false,
    status: band($T.deploy_frequency; $cur.per_week),
    trend: trend($T.deploy_frequency; $cur.per_week; $prev.per_week),
    target: "On track at \($T.deploy_frequency.green)+ per week; watch below \($T.deploy_frequency.amber).",
    meaning: "How many times per week your work actually reaches users. More frequent, smaller releases mean less risk per release and faster feedback.",
    source: (if $dsrc == "merges" then "Stand-in: merges to the main branch (no releases or production deployments found)."
             elif $dsrc == "tags" then "Git tags in the period."
             elif $dsrc == "releases" then "GitHub Releases (non-draft, non-prerelease)."
             else "GitHub production deployments." end),
    series: ($raw | sparkline(. as $c | [$c.raw.deploys[] | select(.at | inw($c.s; $c.e))] | length))
  } as $k1
| ($k1 + {
    drivers: ([
      (if $gap != null and ($gap.gap > 3 * 86400)
       then {label: "Longest gap between ships", detail: "\(($gap.gap / 86400) | r1) days (\($gap.from | todate | day) → \($gap.to | todate | day))"} else empty end),
      (if $failed_deploys > 0 then {label: "Failed production deployments", detail: "\($failed_deploys) of \($cur.deploys)"} else empty end),
      {label: "Previous period", detail: "\($prev.per_week | r1) / week (\($prev.deploys) total)"}
    ]),
    actions: (if $k1.status == "green" then ["Keep shipping at this pace. Stretch goal: move toward on-demand releases (every merge ships)."]
      else [
        (if $cur.deploys == 0 then "Nothing shipped in \($days) days. Find what is blocking the next release and ship the smallest useful piece first."
         else "Ship in smaller pieces, more often. Today you ship \($cur.per_week | r1)× per week; aim for \($T.deploy_frequency.amber)+ first, then \($T.deploy_frequency.green)." end),
        "Pick a release trigger you do not have to think about (every merge to \($raw.branch), or a fixed weekly slot) and automate it so shipping is one click.",
        (if $dsrc == "merges" or $dsrc == "tags" then "Publish GitHub Releases or deployment events so this number reflects real production deploys." else empty end)
      ] end)
  }) as $K1

# ------------------------------------------------------------ 2. lead time for changes
| ($cur.lead | map(.lead)) as $leads
| ($leads | median) as $lmed
| ($cur.lead | map(select(.number != null and .first_review_at != null))) as $staged
| ($staged | map([hrs(.first_commit_at; .created_at), 0] | max) | median) as $s_code
| ($staged | map([hrs(.created_at; .first_review_at), 0] | max) | median) as $s_wait
| ($staged | map([hrs(.first_review_at; .merged_at), 0] | max) | median) as $s_rev
| (if ($staged | length) >= 3 then ([{k: "coding", v: $s_code}, {k: "waiting", v: $s_wait}, {k: "review", v: $s_rev}] | max_by(.v)).k else null end) as $slowest
| ($cur.lead | map(select(.changed_files != null))) as $sized
| ($sized | map(select(.lead > $lmed)) | map(.additions + .deletions) | median) as $big
| ($sized | map(select(.lead <= $lmed)) | map(.additions + .deletions) | median) as $small
| {
    id: "lead_time", name: "Lead time for changes", question: "How fast does an idea reach main?",
    value: ($lmed | r1), unit: "hours", display: ($lmed | fmt_h),
    prev_value: ($prev.lead_median | r1), prev_display: ($prev.lead_median | fmt_h),
    n: ($leads | length), sample_label: plural($leads | length; "PR"),
    low_sample: (($leads | length) < $minn),
    status: band($T.lead_time; $lmed),
    trend: trend($T.lead_time; $lmed; $prev.lead_median),
    target: "On track at \($T.lead_time.green) h or less; watch under \(fmt_d($T.lead_time.amber)) days.",
    meaning: "The typical time from a developer's first commit to that change being merged. Short lead times mean small batches, quick reviews and a healthy pipeline.",
    source: (if $gh then "Median over PRs merged in the period: first commit → merge." else "Median over merge commits in the period: oldest commit on the branch → merge. Squash/rebase merges are not measurable from git alone." end),
    series: ($raw | sparkline(. as $c | [$c.raw.prs[] | select(.merged_at | inw($c.s; $c.e)) | select(.first_commit_at != null) | hrs(.first_commit_at; .merged_at)] | median | r1)),
    drivers: ([
      (if $slowest != null then {label: "Where the time goes (typical PR)",
         detail: "coding \($s_code | fmt_h) · waiting for first review \($s_wait | fmt_h) · review to merge \($s_rev | fmt_h)"} else empty end),
      (if $big != null and $small != null and $small > 0 and ($big / $small) >= 1.5
       then {label: "Slow PRs are bigger", detail: "median \($big | r0) changed lines vs \($small | r0) for faster ones"} else empty end),
      ($cur.lead | sort_by(-.lead) | .[0:3][] | {label: "Slowest: \(if .number != null then "#\(.number) " else "" end)\(.title[0:70])", detail: (.lead | fmt_h), url: .url})
    ]),
    actions: (if $lmed == null then ["Not enough merged work in this period to measure."]
      elif band($T.lead_time; $lmed) == "green" then ["Lead time is healthy. Protect it: keep PRs small and reviews prompt."]
      else [
        (if $slowest == "coding" then "Work sits on branches before a PR is opened (typically \($s_code | fmt_h)). Open draft PRs early and slice work into pieces that fit in 1–2 days."
         elif $slowest == "waiting" then "PRs wait \($s_wait | fmt_h) for a first review, the biggest delay. Agree a first-response target (e.g. 4 working hours) and set a daily review slot."
         elif $slowest == "review" then "After the first review, PRs take another \($s_rev | fmt_h) to merge. Look at rounds of feedback, slow CI, and flaky checks. A PR template with a self-review checklist cuts back-and-forth."
         else "Find where the time goes: break one slow PR down into coding, waiting and review. Start with the three slowest below." end),
        (if $big != null and $small != null and $small > 0 and ($big / $small) >= 1.5 then "Keep PRs under about 400 changed lines. The slow PRs here are \((($big / $small) * 10 | round) / 10)× bigger than the fast ones." else empty end),
        "Review the three slowest PRs below in your next retro and ask what would have made each one half the size."
      ] end)
  } as $K2

# ------------------------------------------------------------ 3. change failure rate
| ($cur.prs | length) as $changes
| ($cur.reverts | length) as $nrev
| {
    id: "change_failure", name: "Change failure rate", question: "How often does a change break things?",
    value: ($cur.cfr | r1), unit: "percent", display: (if $cur.cfr == null then "–" else "\($cur.cfr | r1)%" end),
    prev_value: ($prev.cfr | r1), prev_display: (if $prev.cfr == null then "–" else "\($prev.cfr | r1)%" end),
    n: $changes, sample_label: "\($nrev) of \(plural($changes; "change"))",
    low_sample: ($changes < ($minn * 2)),
    status: band($T.change_failure; $cur.cfr),
    trend: trend($T.change_failure; $cur.cfr; $prev.cfr),
    target: "On track at \($T.change_failure.green)% or less; watch under \($T.change_failure.amber)%.",
    meaning: "Of every 100 changes you ship, how many need a revert, rollback or hotfix. It balances speed: shipping fast only counts if it stays stable.",
    source: "Merged PRs titled \"Revert…\" or labelled revert / rollback / hotfix, divided by all merged PRs in the period.",
    series: ($raw | sparkline(. as $c | [$c.raw.prs[] | select(.merged_at | inw($c.s; $c.e))] as $p | if ($p | length) == 0 then null else (100 * ($p | map(select(.is_revert)) | length) / ($p | length) | r1) end)),
    drivers: ([
      ($cur.reverts[0:5][] | {label: "\(if .number != null then "#\(.number) " else "" end)\(.title[0:70])", detail: "merged \(.merged_at | day)", url: .url}),
      (if $failed_deploys > 0 then {label: "Failed production deployments", detail: "\($failed_deploys) in the period"} else empty end)
    ]),
    actions: (if $cur.cfr == null then ["No merged changes in this period to measure."]
      elif $nrev == 0 then ["No reverts or hotfixes this period. Keep labelling hotfix PRs (hotfix / rollback / revert) so this stays honest."]
      else [
        "For each revert below, spend 10 minutes on \"what would have caught this before merge?\" and file the answer as a ticket (a test, a required CI check, a feature flag).",
        "Make the checks that matter required to merge (tests, lint, type check) in branch protection so a red build cannot ship.",
        "Roll out risky changes behind a feature flag or to a small slice first, so a bad change is a toggle, not a revert."
      ] end)
  } as $K3

# ------------------------------------------------------------ 4. time to restore (bug fix time)
| ($raw.bugs | map(select(.state == "open") | . + {age: hrs(.created_at; ($now | todate))}) | sort_by(-.age)) as $open
| {
    id: "time_to_restore", name: "Time to restore", question: "When something breaks, how fast do we fix it?",
    value: ($cur.ttr_median | r1), unit: "hours", display: ($cur.ttr_median | fmt_h),
    prev_value: ($prev.ttr_median | r1), prev_display: ($prev.ttr_median | fmt_h),
    n: ($cur.fixed | length), sample_label: plural($cur.fixed | length; "fixed bug"),
    low_sample: (($cur.fixed | length) < $minn),
    status: (if $gh then band($T.time_to_restore; $cur.ttr_median) else "na" end),
    trend: trend($T.time_to_restore; $cur.ttr_median; $prev.ttr_median),
    target: "On track at \($T.time_to_restore.green) h or less; watch under \(fmt_d($T.time_to_restore.amber)) days.",
    meaning: "The typical time from a bug or incident being reported to it being closed. This is how long users live with a problem.",
    source: (if $gh then "Median open → closed time of issues labelled bug / incident / outage / regression / sev / p0 / p1 / critical / hotfix, closed in the period." else "Needs GitHub issue data." end),
    series: ($raw | sparkline(. as $c | [$c.raw.bugs[] | select(.closed_at | inw($c.s; $c.e)) | hrs(.created_at; .closed_at)] | median | r1)),
    drivers: ([
      (if ($open | length) > 0 then {label: "Open bugs right now", detail: "\($open | length), oldest is \(fmt_d($open[0].age)) days old"} else empty end),
      ($open[0:3][] | {label: "Oldest open: #\(.number) \(.title[0:60])", detail: "\(fmt_d(.age)) days old", url: .url}),
      ($cur.fixed | map(. + {t: hrs(.created_at; .closed_at)}) | sort_by(-.t) | .[0:2][] | {label: "Slowest fix: #\(.number) \(.title[0:60])", detail: (.t | fmt_h), url: .url})
    ]),
    actions: (if ($raw.bugs | length) == 0 then
        (if $gh then ["No issues labelled bug or incident were found. Label bugs consistently (bug, incident, outage) so this KPI can be measured."] else ["Run with GitHub data (gh signed in) to measure this."] end)
      elif $cur.ttr_median == null then ["No bugs were closed in this period. Check the open bugs below; the oldest are the first candidates."]
      elif band($T.time_to_restore; $cur.ttr_median) == "green" then ["Fixes land quickly. Keep a named owner on every bug and incident."]
      else [
        "Triage new bugs daily and give each an owner within one working day. Unowned bugs are the ones that age.",
        (if ($open | length) > 0 and $open[0].age > 24 * 30 then "Close or re-triage bugs older than 30 days (oldest is \(fmt_d($open[0].age)) days). Either fix it, schedule it, or accept it and close it." else empty end),
        "Keep a rollback path for every release so restoring service is a revert, not a rewrite."
      ] end)
  } as $K4

# ------------------------------------------------------------ 5. review wait
| ($raw.open_prs | map(select(.first_review_at == null) | . + {age: hrs(.created_at; ($now | todate))}) | sort_by(-.age)) as $waiting
| {
    id: "review_wait", name: "Review wait time", question: "How long does a PR wait for its first review?",
    value: ($cur.wait_median | r1), unit: "hours", display: ($cur.wait_median | fmt_h),
    prev_value: ($prev.wait_median | r1), prev_display: ($prev.wait_median | fmt_h),
    n: ($cur.rev | length), sample_label: plural($cur.rev | length; "reviewed PR"),
    low_sample: (($cur.rev | length) < $minn),
    status: (if $gh then band($T.review_wait; $cur.wait_median) else "na" end),
    trend: trend($T.review_wait; $cur.wait_median; $prev.wait_median),
    target: "On track at \($T.review_wait.green) h or less; watch under \($T.review_wait.amber) h.",
    meaning: "How long a finished PR sits before a teammate first looks at it. Waiting is the most common (and cheapest to fix) delay in the whole process.",
    source: (if $gh then "Median PR opened → first review by a human other than the author, for PRs merged in the period. Bots are ignored." else "Needs GitHub PR data." end),
    series: ($raw | sparkline(. as $c | [$c.raw.prs[] | select(.merged_at | inw($c.s; $c.e)) | select(.first_review_at != null) | [hrs(.created_at; .first_review_at), 0] | max] | median | r1)),
    drivers: ([
      (if $cur.unreviewed_pct != null and $cur.unreviewed_pct > 0 then {label: "Merged with no review", detail: "\($cur.unreviewed_pct | r0)% of PRs this period"} else empty end),
      ($waiting[0:3][] | {label: "Waiting now: #\(.number) \(.title[0:60])", detail: "\(.age | fmt_h) and no review", url: .url}),
      ($cur.rev | sort_by(-.wait) | .[0:2][] | {label: "Slowest first review: #\(.number) \(.title[0:55])", detail: (.wait | fmt_h), url: .url})
    ]),
    actions: (if ($gh | not) then ["Run with GitHub data (gh signed in) to measure this."]
      elif $cur.wait_median == null and ($cur.unreviewed_pct // 0) > 0 then ["PRs are merging with no recorded review. Require at least one approval in branch protection."]
      elif $cur.wait_median == null then ["Not enough reviewed PRs in this period to measure."]
      elif band($T.review_wait; $cur.wait_median) == "green" and (($cur.unreviewed_pct // 0) <= 20) then ["Reviews are prompt. Keep it that way: review before starting new work."]
      else [
        "Agree a first-review target of \($T.review_wait.green) working hours, and make reviewing the first thing people do each morning.",
        (if ($waiting | length) > 0 then "\(plural($waiting | length; "PR")) are waiting for a first review right now (listed below). Clear those first." else empty end),
        (if ($cur.unreviewed_pct // 0) > 20 then "\($cur.unreviewed_pct | r0)% of PRs merged with no review. Require one approval in branch protection and use CODEOWNERS to auto-request reviewers." else "Use CODEOWNERS or auto-assignment so every PR gets a named reviewer the moment it opens." end)
      ] end)
  } as $K5

| [$K1, $K2, $K3, $K4, $K5] as $ks
| ($ks | map(select(.status == "green")) | length) as $g
| ($ks | map(select(.status == "amber")) | length) as $a
| ($ks | map(select(.status == "red")) | length) as $r
| ($ks | map(select(.status == "na")) | length) as $na
| ($ks | map(select(.status == "red" or .status == "amber"))
        | sort_by([(if .status == "red" then 0 else 1 end), (if .trend.dir == "worse" then 0 else 1 end)])) as $focus
| {
    repo: $raw.repo, branch: $raw.branch, mode: $raw.mode, days: $days, deploy_source: $dsrc,
    generated_at: ($now | todate),
    period: {start: ($w0 | todate | day), end: ($now | todate | day), prev_start: ($p0 | todate | day)},
    summary: {green: $g, amber: $a, red: $r, na: $na, total: 5},
    headline: (if ($focus | length) == 0
      then "\($g) of \(5 - $na) KPIs are on track. Nothing needs fixing right now."
      else "\($g) of \(5 - $na) KPIs are on track. Biggest opportunity: \($focus[0].name | ascii_downcase)." end),
    top_actions: ($focus[0:3] | map({kpi: .name, status: .status, action: .actions[0]})),
    kpis: $ks,
    notes: ($raw.notes + (if ($ks | map(select(.low_sample)) | length) > 0
      then ["Low sample size for: \($ks | map(select(.low_sample) | .name) | join(", ")). Treat those numbers as a hint, not a verdict."] else [] end))
  }
