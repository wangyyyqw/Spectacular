#!/usr/bin/perl
# 生成《开发方案》的任务总览表与进度看板，并校验任务清单一致性。
# 用法：perl tool/render_plan.pl [方案/开发方案.md]
use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';

my $path = shift @ARGV // '方案/开发方案.md';
open my $in, '<:encoding(UTF-8)', $path or die "无法读取 $path: $!";
my @lines = <$in>;
close $in;

my ($stage, $module);
my @tasks;
my %seen;
my $cur;
my %stage_claim;

for my $raw (@lines) {
    my $line = $raw;
    chomp $line;
    if ($line =~ /^## \d+\. P(\d) .*?（(\d+) 项 \/ (\d+)h）/) {
        $stage = $1;
        $stage_claim{$1} = [$2, $3];
        $module = undef;
        next;
    }
    if ($line =~ /^### (P\d\.\d+ .+)$/) {
        $module = $1;
        next;
    }
    if ($line =~ /^- \[([ x])\] \*\*(P(\d)-(\d\d)) (.+?)\*\* ｜ (\d+)h\s*$/) {
        die "任务编号重复: $2\n" if $seen{$2}++;
        $cur = {
            id => $2, stage => $3, num => $4 + 0, title => $5,
            hours => $6 + 0, done => ($1 eq 'x'), module => ($module // '(未分组)'),
            fields => {},
        };
        push @tasks, $cur;
        next;
    }
    if ($cur && $line =~ /^(?: {2}-) (目标|产出|依赖|验收|参考)：(.*)$/) {
        $cur->{fields}{$1} = $2;
        next;
    }
    $cur = undef if $line =~ /^\s*$/;
}

my @errors;
my %required = map { $_ => 1 } qw(目标 产出 依赖 验收 参考);
push @errors, "任务总数应为 200，实际 " . scalar(@tasks) unless @tasks == 200;

my $total_hours = 0;
my (%stage_cnt, %stage_hours, %stage_done_cnt, %stage_done_hours);
my %pos;
for my $t (@tasks) {
    $pos{$t->{id}} = [$t->{stage}, $t->{num}];
    $total_hours += $t->{hours};
    $stage_cnt{$t->{stage}}++;
    $stage_hours{$t->{stage}} += $t->{hours};
    $stage_done_cnt{$t->{stage}}++ if $t->{done};
    $stage_done_hours{$t->{stage}} += $t->{hours} if $t->{done};
    for my $f (keys %required) {
        push @errors, "$t->{id} 缺少字段「$f」" unless exists $t->{fields}{$f};
    }
    my $deps = $t->{fields}{依赖} // '';
    while ($deps =~ /(P\d-\d\d)/g) {
        my $dep = $1;
        push @errors, "$t->{id} 依赖不存在的任务 $dep" unless $pos{$dep};
        my ($ds, $dn) = @{ $pos{$dep} // [0, 0] };
        my $not_earlier = ($ds < $t->{stage}) || ($ds == $t->{stage} && $dn < $t->{num});
        push @errors, "$t->{id} 依赖 $dep 不早于自身" unless $not_earlier;
    }
}
for my $s (sort keys %stage_claim) {
    my ($want_cnt, $want_h) = @{ $stage_claim{$s} };
    my ($got_cnt, $got_h) = ($stage_cnt{$s} // 0, $stage_hours{$s} // 0);
    push @errors, "P$s 标称 $want_cnt 项/$want_h h，实际 $got_cnt 项/$got_h h"
        unless $got_cnt == $want_cnt && $got_h == $want_h;
}
push @errors, "总工时应为 640h，实际 ${total_hours}h" unless $total_hours == 640;

my $done_total = 0;
my $done_hours = 0;
for my $t (@tasks) {
    next unless $t->{done};
    $done_total++;
    $done_hours += $t->{hours};
}
my $pct = @tasks ? sprintf('%.1f', $done_total * 100 / @tasks) : '0.0';

my $progress = "\n| 阶段 | 任务区间 | 任务数 | 完成 | 工时 | 已完成工时 |\n";
$progress .= "|---|---|---:|---:|---:|---:|\n";
my %range;
for my $t (@tasks) {
    $range{$t->{stage}}[0] //= $t->{id};
    $range{$t->{stage}}[1] = $t->{id};
}
for my $s (0 .. 6) {
    $progress .= sprintf("| P%d | %s～%s | %d | %d | %dh | %dh |\n",
        $s, $range{$s}[0], $range{$s}[1],
        $stage_cnt{$s} // 0, $stage_done_cnt{$s} // 0,
        $stage_hours{$s} // 0, $stage_done_hours{$s} // 0);
}
$progress .= sprintf("| 合计 | 200 项 | %d | %d | %dh | %dh |\n",
    scalar(@tasks), $done_total, $total_hours, $done_hours);
$progress .= sprintf("\n- [%s] 总进度：%d / %d 项，%dh / %dh（%s%%）\n",
    $done_total == @tasks ? 'x' : ' ', $done_total, scalar(@tasks),
    $done_hours, $total_hours, $pct);
$progress .= "\n> 本表由 `perl tool/render_plan.pl` 生成；勾选任务正文后重跑脚本，本表与任务总览表同步更新。\n";

my $overview = "\n| 状态 | 编号 | 任务 | 模块 | 工时 | 依赖 |\n";
$overview .= "|---|---|---|---|---:|---|\n";
for my $t (@tasks) {
    my $title = $t->{title};
    $title =~ s/\|/\\|/g;
    my $mark = $t->{done} ? '[x]' : '[ ]';
    my $deps = $t->{fields}{依赖} // '';
    $deps =~ s/\|/\\|/g;
    $overview .= sprintf("| %s | %s | %s | %s | %dh | %s |\n",
        $mark, $t->{id}, $title, $t->{module}, $t->{hours}, $deps);
}
$overview .= "\n> 状态列是字面 Markdown 复选框（GitHub 表格不渲染可点击控件）。以任务正文的复选框为准，重跑脚本会同步本表。\n";

my $new = join '', @lines;
my $ok_progress = $new =~ s{(### 1\.1 [^\n]*\n).*?(?=### 1\.2 里程碑)}{$1 . $progress . "\n"}s;
my $ok_overview = $new =~ s{(## 2\. 任务总览表\n).*?(?=---\n\n## 3\. P0)}{$1 . $overview . "\n"}s;

push @errors, "未找到进度看板区块（§1.1）" unless $ok_progress;
push @errors, "未找到任务总览表区块（§2）" unless $ok_overview;

if (@errors) {
    print STDERR "校验失败（" . scalar(@errors) . " 项）：\n";
    print STDERR " - $_\n" for @errors;
    exit 1;
}

open my $fh, '>:encoding(UTF-8)', $path or die "无法写入 $path: $!";
print $fh $new;
close $fh;
print "OK：200 项 / ${total_hours}h，已完成 ${done_total} 项 / ${done_hours}h（${pct}%），总览与看板已更新。\n";
