# -*- coding: utf-8 -*-
"""AC-4 验收：从 prototype/index.html 的数据集回归参考图黄金算例"""
import re, pathlib, collections, datetime
src = pathlib.Path(r'D:\DSH\Account\prototype\index.html').read_text(encoding='utf-8')
rows = re.findall(r"tx\('(\d{4}-\d{2}-\d{2})','(EXPENSE|INCOME)','(\w+)',([\d.]+),'([^']*)'\)", src)
print('数据集记录数:', len(rows))
recs = [dict(date=d, type=t, cat=c, cents=round(float(a)*100), note=n) for d,t,c,a,n in rows]

D = lambda s: datetime.date(*map(int, s.split('-')))
TODAY = D('2026-10-09')
ws, we = D('2026-10-05'), D('2026-10-11')

week = [r for r in recs if ws <= D(r['date']) <= we]
exp = sum(r['cents'] for r in week if r['type']=='EXPENSE')
inc = sum(r['cents'] for r in week if r['type']=='INCOME')
elapsed = (min(TODAY, we) - ws).days + 1
avg = round(exp/elapsed)

day = collections.Counter()
for r in week:
    if r['type']=='EXPENSE': day[r['date']] += r['cents']
cat = collections.Counter()
for r in week:
    if r['type']=='EXPENSE': cat[r['cat']] += r['cents']

NAME = {'coin':'投资','tissue':'日用','bus':'交通','food':'餐饮','baby':'孩子',
        'plane':'旅行','car':'汽车','cross':'医疗','cupcake':'零食'}
EXPECT_PCT = {'投资':35.9,'日用':25.9,'交通':19.0,'餐饮':6.0,'孩子':4.3,'旅行':3.5,'汽车':2.7}
EXPECT_AMT = {'投资':818,'日用':590,'交通':434,'餐饮':136,'孩子':99,'旅行':80,'汽车':62}
ok = True
def chk(label, got, want, tol=0.0):
    global ok
    good = abs(got-want) <= tol if isinstance(want,(int,float)) else got==want
    ok = ok and good
    print('  %-42s got=%-10s want=%-10s %s' % (label, got, want, 'PASS' if good else 'FAIL'))

print('\n[1] 周期与平均值')
chk('已过天数 (2026-10-05 ~ 2026-10-09)', elapsed, 5)
chk('本周总支出', round(exp/100,2), 2281.00)
chk('本周平均值 (2281.00 / 5)', round(avg/100,2), 456.20)

print('\n[2] 分类金额与占比')
for k, want in EXPECT_AMT.items():
    key = [c for c,n in NAME.items() if n==k][0]
    chk('%s 金额' % k, round(cat[key]/100,2), float(want))
for k, want in EXPECT_PCT.items():
    key = [c for c,n in NAME.items() if n==k][0]
    chk('%s 占比%%' % k, round(cat[key]*1000/exp)/10, want, 0.05)
pct_sum = round(sum(round(cat[[c for c,n in NAME.items() if n==k][0]]*1000/exp)/10 for k in EXPECT_AMT), 1)
chk('占位六项之和（应≈100，其余为医疗55/零食7）', pct_sum, pct_sum) # 仅打印
print('     全部九类占比合计 = %.1f%%' % (sum(round(v*1000/exp)/10 for v in cat.values())))

print('\n[3] 折线图 y 轴上界 = 单日最大值，且各日点值与参考图折线一致')
EXPECT_DAILY = {'2026-10-05':1045.00, '2026-10-06':152.00, '2026-10-07':97.00,
                '2026-10-08':53.00, '2026-10-09':934.00,
                '2026-10-10':0.00, '2026-10-11':0.00}
for ds, want in EXPECT_DAILY.items():
    chk('日点值 %s' % ds, round(day.get(ds,0)/100,2), want)
chk('单日最大值', round(max(day.values())/100,2), 1045.00)
print('     日合计:', {d[5:]: round(v/100,2) for d,v in sorted(day.items())})

print('\n[4] 10-09 当日构成（与参考图逐行一致）')
rows09 = [r for r in recs if r['date']=='2026-10-09']
chk('10-09 支出', round(sum(r['cents'] for r in rows09 if r['type']=='EXPENSE')/100,2), 934.00)
chk('10-09 收入', round(sum(r['cents'] for r in rows09 if r['type']=='INCOME')/100,2), 50.00)
print('     行序:', [ (r['note'], -r['cents']/100 if r['type']=='EXPENSE' else r['cents']/100) for r in rows09 ])

print('\n[5] 10 月头部合计（参考图 REF-3）')
oct_ = [r for r in recs if r['date'].startswith('2026-10')]
chk('10 月支出合计', round(sum(r['cents'] for r in oct_ if r['type']=='EXPENSE')/100,2), 15887.00)
chk('10 月收入合计', round(sum(r['cents'] for r in oct_ if r['type']=='INCOME')/100,2), 3697.00)

print('\n结果:', 'ALL PASS' if ok else 'HAS FAILURE')
