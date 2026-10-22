#!/usr/bin/perl
# 同步《开发方案》主文档的进度看板、任务总览表，并更新各阶段文件顶部进度。
# 用法：perl tool/render_plan.pl [方案/开发方案.md]
use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';

my $main_path = shift @ARGV // '方案/开发方案.md';
my $dir = '方案/开发方案';
my $main_rel = '开发方案';   # 主文档引用阶段文件的相对目录

my @stages = (
    { n => 0, file => 'P0-工程准备与风险验证.md' },
    { n => 1, file => 'P1-M0-最小可读链路.md' },
    { n => 2, file => 'P2-M1-排版质量.md' },
    { n => 3, file => 'P3-M2-资源浮动与容错.md' },
    { n => 4, file => 'P4-M3-业务闭环.md' },
    { n => 5, file => 'P5-M4-高级排版.md' },
    { n => 6, file => 'P6-M5-打磨与发布.md' },
);

my @errors;
my @tasks;
my %seen;
my %stage_claim;
my (%stage_cnt, %stage_hours, %stage_done_cnt, %stage_done_hours, %stage_range);
my %stage_content;

for my $st (@stages) {
    my $path = "$dir/$st->{file}";
    open my $in, '<:encoding(UTF-8)', $path or do {
        push @errors, "无法读取 $path";
        next;
    };
    local $/;
    my $content = <$in>;
    close $in;

    my ($claim_cnt, $claim_h);
    if ($content =~ /^# P\d .*?（(\d+) 项 \/ (\d+)h）/m) {
        ($claim_cnt, $claim_h) = ($1, $2);
    } else {
        push @errors, "$path 缺少阶段标题（项数/工时）";
    }

    my $module;
    my @stage_tasks;
    for my $line (split /\n/, $content) {
        if ($line =~ /^### (P\d\.\d+ .+)$/) { $module = $1; next; }
        if ($line =~ /^- \[([ x])\] \*\*(P(\d)-(\d\d)) (.+?)\*\* ｜ (\d+)h\s*$/) {
            my $id = $2;
            push @errors, "任务编号重复: $id" if $seen{$id}++;
            my $t = {
                id => $id, stage => $3, num => $4 + 0, title => $5,
                hours => $6 + 0, done => ($1 eq 'x'),
                module => ($module // '(未分组)'),
                file => $st->{file},
                fields => {},
            };
            push @stage_tasks, $t;
            push @tasks, $t;
            next;
        }
    }
    # 字段按任务块归属
    my $cur;
    for my $line (split /\n/, $content) {
        if ($line =~ /^- \[([ x])\] \*\*(P\d-\d\d) /) {
            ($cur) = grep { $_->{id} eq $2 } @stage_tasks;
            next;
        }
        if ($cur && $line =~ /^(?: {2}-) (目标|产出|依赖|验收|参考)：(.*)$/) {
            $cur->{fields}{$1} = $2;
        }
    }

    $stage_claim{$st->{n}} = [$claim_cnt // 0, $claim_h // 0];
    $stage_content{$st->{n}} = \$content;
    for my $t (@stage_tasks) {
        $stage_cnt{$st->{n}}++;
        $stage_hours{$st->{n}} += $t->{hours};
        $stage_done_cnt{$st->{n}}++ if $t->{done};
        $stage_done_hours{$st->{n}} += $t->{hours} if $t->{done};
        $stage_range{$st->{n}}[0] //= $t->{id};
        $stage_range{$st->{n}}[1] = $t->{id};
    }
}

my %required = map { $_ => 1 } qw(目标 产出 依赖 验收 参考);
push @errors, "任务总数应为 200，实际 " . scalar(@tasks) unless @tasks == 200;

my $total_hours = 0;
my %pos;
for my $t (@tasks) {
    $pos{$t->{id}} = [$t->{stage}, $t->{num}];
    $total_hours += $t->{hours};
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
for my $st (@stages) {
    my ($want_cnt, $want_h) = @{ $stage_claim{$st->{n}} // [0, 0] };
    my ($got_cnt, $got_h) = ($stage_cnt{$st->{n}} // 0, $stage_hours{$st->{n}} // 0);
    push @errors, "P$st->{n} 标称 $want_cnt 项/$want_h h，实际 $got_cnt 项/$got_h h"
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

# 各阶段文件顶部进度行
for my $st (@stages) {
    next unless $stage_content{$st->{n}};
    my $cnt = $stage_cnt{$st->{n}} // 0;
    my $done = $stage_done_cnt{$st->{n}} // 0;
    my $h = $stage_hours{$st->{n}} // 0;
    my $dh = $stage_done_hours{$st->{n}} // 0;
    my $sp = $h ? sprintf('%.0f', $dh * 100 / $h) : '0';
    my $line = sprintf('> 进度：%d / %d 项 · %dh / %dh（%s%%）', $done, $cnt, $dh, $h, $sp);
    my $path = "$dir/$st->{file}";
    open my $fh, '>:encoding(UTF-8)', $path or die "无法写入 $path: $!";
    my $content = ${ $stage_content{$st->{n}} };
    unless ($content =~ s/^> 进度：.*$/$line/m) {
        push @errors, "$path 缺少进度行";
        close $fh;
        next;
    }
    print $fh $content;
    close $fh;
}

# 主文档
open my $in, '<:encoding(UTF-8)', $main_path or die "无法读取 $main_path: $!";
my @lines = <$in>;
close $in;
my $new = join '', @lines;

my $progress = "\n| 阶段 | 任务 | 完成 | 工时 | 已完成工时 | 文件 |\n";
$progress .= "|---|---:|---:|---:|---:|---|\n";
for my $st (@stages) {
    $progress .= sprintf("| P%d | %d | %d | %dh | %dh | [%s](%s/%s) |\n",
        $st->{n}, $stage_cnt{$st->{n}} // 0, $stage_done_cnt{$st->{n}} // 0,
        $stage_hours{$st->{n}} // 0, $stage_done_hours{$st->{n}} // 0,
        $st->{file}, $main_rel, $st->{file});
}
$progress .= sprintf("| 合计 | %d | %d | %dh | %dh | 7 个阶段文件 |\n",
    scalar(@tasks), $done_total, $total_hours, $done_hours);
$progress .= sprintf("\n- [%s] 总进度：%d / %d 项，%dh / %dh（%s%%）\n",
    $done_total == @tasks ? 'x' : ' ', $done_total, scalar(@tasks),
    $done_hours, $total_hours, $pct);
$progress .= "\n> 本表由 `perl tool/render_plan.pl` 生成；勾选阶段文件中的任务后重跑脚本，本表、总览表与阶段文件进度同步更新。\n";

my $overview = "\n| 状态 | 编号 | 任务 | 模块 | 工时 | 依赖 |\n";
$overview .= "|---|---|---|---|---:|---|\n";
for my $t (@tasks) {
    my $title = $t->{title};
    $title =~ s/\|/\\|/g;
    my $mark = $t->{done} ? '[x]' : '[ ]';
    my $deps = $t->{fields}{依赖} // '';
    $deps =~ s/\|/\\|/g;
    $overview .= sprintf("| %s | [%s](%s/%s) | %s | %s | %dh | %s |\n",
        $mark, $t->{id}, $main_rel, $t->{file}, $title, $t->{module}, $t->{hours}, $deps);
}
$overview .= "\n> 状态列是字面 Markdown 复选框（GitHub 表格不渲染可点击控件）。以阶段文件中任务正文的复选框为准，重跑脚本会同步本表。\n";

my $ok_progress = $new =~ s{(### 1\.1 [^\n]*\n).*?(?=### 1\.2 里程碑)}{$1$progress\n}s;
my $ok_overview = $new =~ s{(## 2\. 任务总览表\n).*?(?=---\n\n## 3\. 阶段文件)}{$1$overview\n}s;

push @errors, "未找到进度看板区块（§1.1）" unless $ok_progress;
push @errors, "未找到任务总览表区块（§2）" unless $ok_overview;

if (@errors) {
    print STDERR "校验失败（" . scalar(@errors) . " 项）：\n";
    print STDERR " - $_\n" for @errors;
    exit 1;
}

open my $out, '>:encoding(UTF-8)', $main_path or die "无法写入 $main_path: $!";
print $out $new;
close $out;
print "OK：200 项 / ${total_hours}h，已完成 ${done_total} 项 / ${done_hours}h（${pct}%），主文档与 7 个阶段文件已同步。\n";
