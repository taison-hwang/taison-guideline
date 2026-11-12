import pickle, sys, collections, statistics as st
ss, errs, errday = pickle.load(open(sys.argv[1], 'rb'))
ss = [s for s in ss if s['amsg'] > 0]
print('sessions with assistant msgs:', len(ss))
def q(a, p): a = sorted(a); return a[min(len(a)-1, int(len(a)*p))]
def grp(r): return 'worker' if r.startswith('worker') else ('verifier' if r.startswith('verif') else (r or '(없음)'))
by = collections.defaultdict(list)
for s in ss: by[grp(s['role'])].append(s)
print('role\tn\trenderMB(sum)\trenderKB(med/p90/max)\tpeak_k(med/p90/max)\tcompacts\tcost$\ttoolcalls\ttoolerr')
for r, l in sorted(by.items(), key=lambda x: -len(x[1])):
    rk = [s['render']/1e3 for s in l]; pk = [s['peak']/1e3 for s in l]
    print(f"{r}\t{len(l)}\t{sum(rk)/1e3:.1f}\t{st.median(rk):.0f}/{q(rk,.9):.0f}/{max(rk):.0f}\t{st.median(pk):.0f}/{q(pk,.9):.0f}/{max(pk):.0f}\t{sum(s['compacts'] for s in l)}\t{sum(s['cost'] for s in l):.0f}\t{sum(s['tools'] for s in l)}\t{sum(s['terr'] for s in l)}")
rk = [s['render'] for s in ss]
print('total render MB', sum(rk)/1e6, 'raw MB', sum(s['bytes'] for s in ss)/1e6, 'total cost', sum(s['cost'] for s in ss))
print('render > 400KB:', sum(1 for x in rk if x > 400e3), ' > 800KB:', sum(1 for x in rk if x > 800e3), ' >2MB:', sum(1 for x in rk if x > 2e6))
days = collections.defaultdict(lambda: [0, 0, 0.0])
for s in ss:
    d = s['start'][:10]; days[d][0] += 1; days[d][1] += s['render']; days[d][2] += s['cost']
print('day\tsessions\trenderMB\tcost$')
for d in sorted(days): print(f"{d}\t{days[d][0]}\t{days[d][1]/1e6:.1f}\t{days[d][2]:.0f}")
print('models', collections.Counter(s['model'] for s in ss))
tot_tools = sum(s['tools'] for s in ss); tot_err = sum(s['terr'] for s in ss)
print('tool calls', tot_tools, 'errors', tot_err, f'{tot_err/tot_tools:.1%}')
rec = [(len(v), sum(v.values()), k) for k, v in errs.items()]
multi = [r for r in rec if r[0] >= 3]
print('distinct signatures', len(rec), '; in >=3 sessions:', len(multi), 'covering errors', sum(r[1] for r in multi), 'of', sum(r[1] for r in rec))
print('in >=5 sessions:', len([r for r in rec if r[0] >= 5]), 'covering', sum(r[1] for r in rec if r[0] >= 5))
for n, c, k in sorted(multi, reverse=True)[:45]:
    ds = sorted(d for d in errday[k] if d)
    print(f"{n}s {c}x {ds[0][5:]}~{ds[-1][5:]} | {k}")
