/// NLU 服务 (v1.3 MVP)
///
/// 把中文一句话解析成结构化记账数据
///
/// v1.3 用本地规则解析 (mock); 后续可切 DeepSeek API
library;

import 'package:http/http.dart' as http;
import 'dart:convert';

class ParsedTx {
  final double? amount;
  final String? categoryId; // cat.food, cat.transport, ...
  final String? categoryName;
  final DateTime? date;
  final String? note;
  final double confidence; // 0-1
  final String? rawText;

  ParsedTx({
    this.amount,
    this.categoryId,
    this.categoryName,
    this.date,
    this.note,
    this.confidence = 0,
    this.rawText,
  });

  bool get isEmpty => amount == null && categoryId == null;

  Map<String, dynamic> toMap() => {
        'amount': amount,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'date': date?.toIso8601String(),
        'note': note,
        'confidence': confidence,
        'rawText': rawText,
      };
}

/// 抽象 NLU Provider — 后续可换 DeepSeek
abstract class NluProvider {
  Future<ParsedTx> parse(String text);
}

/// MVP: 本地规则解析
class LocalRuleNluProvider implements NluProvider {
  /// 关键词 → 分类 id 映射 (子串匹配)
  static const _categoryKeywords = <String, String>{
    // 支出
    '餐': 'cat.food',
    '饭': 'cat.food',
    '吃': 'cat.food',
    '外卖': 'cat.food',
    '超市': 'cat.market',
    '市场': 'cat.market',
    '打车': 'cat.transport',
    '出租': 'cat.transport',
    '滴滴': 'cat.transport',
    '的士': 'cat.transport',
    '地铁': 'cat.transport',
    '公交': 'cat.transport',
    '高铁': 'cat.transport',
    '火车': 'cat.transport',
    '飞机': 'cat.transport',
    '加油': 'cat.car',
    '停车': 'cat.car',
    '水果': 'cat.fruit',
    '苹果': 'cat.fruit',
    '香蕉': 'cat.fruit',
    '奶茶': 'cat.drink',
    '咖啡': 'cat.drink',
    '茶': 'cat.drink',
    '水': 'cat.drink',
    '衣服': 'cat.dress',
    '鞋': 'cat.dress',
    '裤子': 'cat.dress',
    '手机': 'cat.digital',
    '电脑': 'cat.digital',
    '酒店': 'cat.travel',
    '旅行': 'cat.travel',
    '机票': 'cat.travel',
    '房租': 'cat.housing',
    '水电': 'cat.housing',
    '医保': 'cat.medical',
    '药': 'cat.medical',
    '孩子': 'cat.kid',
    '奶粉': 'cat.kid',
    '学费': 'cat.education',
    '报名': 'cat.education',
    '书': 'cat.book',
    '红包': 'cat.receive',
    '理发': 'cat.beauty',
    '护肤': 'cat.beauty',
    // 收入
    '工资': 'cat.salary',
    '薪水': 'cat.salary',
    '奖金': 'cat.bonus',
    '补贴': 'cat.subsidy',
    '兼职': 'cat.parttime',
    '投资': 'cat.invest',
    '理财': 'cat.invest',
    '退款': 'cat.refund',
  };

  /// 中文数字 → 阿拉伯数字
  static const _cnDigits = {
    '零': 0, '一': 1, '二': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
    '十': 10, '百': 100, '千': 1000, '万': 10000,
    '两': 2,
  };

  @override
  Future<ParsedTx> parse(String text) async {
    if (text.isEmpty) return ParsedTx(rawText: text, confidence: 0);

    final t = text.trim();

    // 1. 提取金额
    final amount = _extractAmount(t);

    // 2. 提取日期
    final date = _extractDate(t);

    // 3. 识别分类
    final cat = _extractCategory(t);

    // 4. 备注: 去除金额/日期/分类关键词后剩余
    final note = _extractNote(t);

    final confidence = (amount != null ? 0.5 : 0.0) +
        (cat != null ? 0.3 : 0.0) +
        (date != null ? 0.1 : 0.0) +
        (note != null ? 0.1 : 0.0);

    return ParsedTx(
      amount: amount,
      categoryId: cat?.$1,
      categoryName: cat?.$2,
      date: date,
      note: note,
      confidence: confidence.clamp(0, 1),
      rawText: text,
    );
  }

  /// 提取金额: 阿拉伯 "35", "35.5", "35块", "35元"
  ///        中文 "三十五", "十五块五"
  double? _extractAmount(String t) {
    // 先把日期部分去掉, 避免 "10月5号" 的 "10" 被当金额
    String cleaned = t;
    cleaned = cleaned.replaceAll(RegExp(r'\d{1,2}月\d{1,2}[日号]?'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\d+\s*天前'), ' ');

    // 找所有数字
    final arRe = RegExp(r'(\d+(?:\.\d+)?)');
    final arMatches = arRe.allMatches(cleaned).toList();
    if (arMatches.isNotEmpty) {
      // 特殊: "7块5" → 7.5 (5 是角)
      if (arMatches.length == 2) {
        final m1 = arMatches[0];
        final m2 = arMatches[1];
        final between = cleaned.substring(m1.end, m2.start);
        final after2 = cleaned.substring(m2.end);
        // 7块5角 形式
        if (between.trim() == '块' &&
            m2.group(1)!.length == 1 && // 单数字
            (after2.isEmpty || !RegExp(r'\d').hasMatch(after2))) {
          return double.parse('${m1.group(1)}.${m2.group(1)}');
        }
        // 7块5 形式 (5 后面什么都没有)
        if (between.trim() == '块' && after2.isEmpty) {
          return double.parse('${m1.group(1)}.${m2.group(1)}');
        }
      }
      // 优先选带 "块/元/毛/角" 的, 否则取最后一个
      RegExpMatch? best;
      for (final m in arMatches) {
        final rest = cleaned.substring(m.end);
        if (rest.isNotEmpty && '块元毛角'.contains(rest[0])) {
          best = m;
          break;
        }
      }
      best ??= arMatches.last;
      return double.parse(best.group(1)!);
    }
    // 试中文数字
    final cnRe = RegExp(r'[零一二三四五六七八九十百千万两]+');
    final cnMatch = cnRe.firstMatch(cleaned);
    if (cnMatch != null) {
      return _parseChineseNumber(cnMatch.group(0)!);
    }
    return null;
  }

  /// 中文数字字符串 → 数字
  double? _parseChineseNumber(String s) {
    if (s.isEmpty) return null;
    // 简单: 万/千/百/十
    double result = 0;
    double current = 0;
    for (final c in s.split('')) {
      final n = _cnDigits[c];
      if (n == null) continue;
      if (n == 10000) {
        result += current * 10000;
        current = 0;
      } else if (n == 1000) {
        result += current * 1000;
        current = 0;
      } else if (n == 100) {
        result += current * 100;
        current = 0;
      } else if (n == 10) {
        if (current == 0) current = 1;
        result += current * 10;
        current = 0;
      } else {
        current = n.toDouble();
      }
    }
    result += current;
    return result == 0 ? null : result;
  }

  /// 提取日期: 今天/昨天/前天/明天/X月X日
  DateTime? _extractDate(String t) {
    final now = DateTime.now();
    if (t.contains('今天') || t.contains('今早') || t.contains('今')) {
      return DateTime(now.year, now.month, now.day);
    }
    if (t.contains('昨天') || t.contains('昨日') || t.contains('昨晚')) {
      final d = now.subtract(const Duration(days: 1));
      return DateTime(d.year, d.month, d.day);
    }
    if (t.contains('前天')) {
      final d = now.subtract(const Duration(days: 2));
      return DateTime(d.year, d.month, d.day);
    }
    if (t.contains('明天') || t.contains('明早')) {
      final d = now.add(const Duration(days: 1));
      return DateTime(d.year, d.month, d.day);
    }
    if (t.contains('刚才') || t.contains('刚') || t.contains('刚刚')) {
      return DateTime(now.year, now.month, now.day);
    }
    // X月X日
    final m = RegExp(r'(\d{1,2})月(\d{1,2})[日号]?').firstMatch(t);
    if (m != null) {
      final month = int.parse(m.group(1)!);
      final day = int.parse(m.group(2)!);
      return DateTime(now.year, month, day);
    }
    // X天前
    final d = RegExp(r'(\d+)\s*天前').firstMatch(t);
    if (d != null) {
      final daysAgo = int.parse(d.group(1)!);
      final dt = now.subtract(Duration(days: daysAgo));
      return DateTime(dt.year, dt.month, dt.day);
    }
    return null;
  }

  /// 分类: 关键词最长匹配
  (String, String)? _extractCategory(String t) {
    String? bestId;
    String? bestKeyword;
    _categoryKeywords.forEach((keyword, catId) {
      if (t.contains(keyword)) {
        // 取最长的关键词 (更精确)
        final kw = bestKeyword;
        if (kw == null || keyword.length > kw.length) {
          bestKeyword = keyword;
          bestId = catId;
        }
      }
    });
    if (bestId == null || bestKeyword == null) return null;
    return (bestId!, bestKeyword!);
  }

  /// 备注: 去除已识别的金额/日期/分类关键词后剩余
  String? _extractNote(String t) {
    String s = t;
    // 去日期
    s = s.replaceAll(RegExp(r'今天|今早|今|昨天|昨日|昨晚|前天|明天|明早|刚才|刚|刚刚|\d+天前|\d{1,2}月\d{1,2}[日号]?'), '');
    // 去金额
    s = s.replaceAll(RegExp(r'\d+(?:\.\d+)?\s*(?:块|元|毛|角)?'), '');
    // 去分类关键词
    _categoryKeywords.forEach((keyword, _) {
      s = s.replaceAll(keyword, '');
    });
    // 去"了"/"的"/"啊"等语气
    s = s.replaceAll(RegExp(r'[了的啊呗呢吧呀哈哦呀喂]'), '');
    s = s.trim();
    return s.isEmpty ? null : s;
  }
}

/// DeepSeek NLU Provider — 完整版 (v1.3 后续启用)
class DeepSeekNluProvider implements NluProvider {
  final String apiKey;
  DeepSeekNluProvider(this.apiKey);

  @override
  Future<ParsedTx> parse(String text) async {
    final prompt = '''你是个人记账助手。从用户口语中提取结构化数据。
输出严格 JSON (不要 markdown):
{
  "amount": number,       // 元, 不能确定就 null
  "category": string,     // 必须是以下之一: cat.food, cat.market, cat.transport, cat.fruit, cat.daily, cat.drink, cat.dress, cat.beauty, cat.phone, cat.house, cat.credit, cat.travel, cat.book, cat.education, cat.medical, cat.housing, cat.kid, cat.pet, cat.digital, cat.car, cat.else, cat.salary, cat.bonus, cat.subsidy, cat.parttime, cat.invest, cat.refund, cat.receive, cat.in_else
  "date": string,         // YYYY-MM-DD, "今天" 或 "昨天"
  "note": string          // 5 字内备注
}

用户: "${text}"
输出:''';

    try {
      final resp = await http.post(
        Uri.parse('https://api.deepseek.com/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.1,
        }),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        // fallback
        return LocalRuleNluProvider().parse(text);
      }
      final body = jsonDecode(resp.body);
      final content = (body['choices'] as List)[0]['message']['content'] as String;
      // content 可能是 ```json { ... } ```, 提取 {...}
      final jsonStr = _extractJson(content);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      final amount = data['amount'] != null ? (data['amount'] as num).toDouble() : null;
      final catId = data['category'] as String?;
      final dateStr = data['date'] as String?;
      DateTime? date;
      if (dateStr == '今天') {
        final n = DateTime.now();
        date = DateTime(n.year, n.month, n.day);
      } else if (dateStr == '昨天') {
        final n = DateTime.now().subtract(const Duration(days: 1));
        date = DateTime(n.year, n.month, n.day);
      } else if (dateStr != null) {
        try {
          date = DateTime.parse(dateStr);
        } catch (_) {}
      }
      return ParsedTx(
        amount: amount,
        categoryId: catId,
        categoryName: catId,
        date: date,
        note: data['note'] as String?,
        confidence: 0.9,
        rawText: text,
      );
    } catch (_) {
      // 网络失败, fallback
      return LocalRuleNluProvider().parse(text);
    }
  }

  String _extractJson(String s) {
    final m = RegExp(r'\{[\s\S]*\}').firstMatch(s);
    return m?.group(0) ?? '{}';
  }
}

/// 单例: 切换 NLU Provider
class NluService {
  static NluProvider _provider = LocalRuleNluProvider();
  static NluProvider get provider => _provider;
  static void useProvider(NluProvider p) => _provider = p;
  static Future<ParsedTx> parse(String text) => _provider.parse(text);
}
