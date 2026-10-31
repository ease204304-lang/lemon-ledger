// NLU 解析器测试 (v1.3 MVP)
// 用本地规则解析 (mock), 5 个真实输入

import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_ledger/services/nlu_service.dart';

void main() {
  final nlu = LocalRuleNluProvider();

  group('金额提取', () {
    test('阿拉伯数字: 午饭20', () async {
      final r = await nlu.parse('午饭20');
      expect(r.amount, equals(20.0));
    });

    test('阿拉伯数字带单位: 打车35块', () async {
      final r = await nlu.parse('打车35块');
      expect(r.amount, equals(35.0));
    });

    test('阿拉伯数字带小数: 买咖啡7块5 → 7.5 (7元5角)', () async {
      final r = await nlu.parse('买咖啡7块5');
      // 中文口语 "7块5" 意指 7.5 元 (5 角)
      expect(r.amount, equals(7.5));
    });

    test('中文数字: 中午吃饭花了四十', () async {
      final r = await nlu.parse('中午吃饭花了四十');
      expect(r.amount, equals(40.0));
    });

    test('中文数字: 一百二十', () async {
      final r = await nlu.parse('买了一百二十的衣服');
      expect(r.amount, equals(120.0));
    });
  });

  group('分类识别', () {
    test('餐饮: 午饭', () async {
      final r = await nlu.parse('午饭20');
      expect(r.categoryId, equals('cat.food'));
    });

    test('交通: 打车', () async {
      final r = await nlu.parse('打车35块');
      expect(r.categoryId, equals('cat.transport'));
    });

    test('饮品: 咖啡', () async {
      final r = await nlu.parse('买咖啡7块');
      expect(r.categoryId, equals('cat.drink'));
    });

    test('工资: 收工资', () async {
      final r = await nlu.parse('刚才收工资15000');
      expect(r.categoryId, equals('cat.salary'));
    });

    test('出租车: 的士 (最长匹配)', () async {
      final r = await nlu.parse('的的士25');
      // "出租" "的士" 都在, "的士" 长度=2, "出租" 长度=2, 取任意
      // 实际: "的士" 在 _categoryKeywords 中, "出租" 也在
      // 都是 2 字, 第一个会赢
      expect(r.categoryId, isIn(['cat.transport']));
    });

    test('服饰: 衣服', () async {
      final r = await nlu.parse('买了一件衣服');
      expect(r.categoryId, equals('cat.dress'));
    });
  });

  group('日期识别', () {
    test('今天', () async {
      final r = await nlu.parse('今天午饭20');
      final now = DateTime.now();
      expect(r.date?.year, equals(now.year));
      expect(r.date?.month, equals(now.month));
      expect(r.date?.day, equals(now.day));
    });

    test('昨天', () async {
      final r = await nlu.parse('昨天打车35块');
      final expected = DateTime.now().subtract(const Duration(days: 1));
      expect(r.date?.day, equals(expected.day));
    });

    test('前天', () async {
      final r = await nlu.parse('前天买了苹果');
      final expected = DateTime.now().subtract(const Duration(days: 2));
      expect(r.date?.day, equals(expected.day));
    });

    test('10月5号', () async {
      final r = await nlu.parse('10月5号买咖啡7块5');
      expect(r.date?.month, equals(10));
      expect(r.date?.day, equals(5));
    });

    test('3天前', () async {
      final r = await nlu.parse('3天前吃饭');
      final expected = DateTime.now().subtract(const Duration(days: 3));
      expect(r.date?.day, equals(expected.day));
    });
  });

  group('综合: 5 个真实场景', () {
    test('"昨天打车35块" → 35 / 交通 / 昨天', () async {
      final r = await nlu.parse('昨天打车35块');
      expect(r.amount, equals(35.0));
      expect(r.categoryId, equals('cat.transport'));
      final expected = DateTime.now().subtract(const Duration(days: 1));
      expect(r.date?.day, equals(expected.day));
    });

    test('"午饭20" → 20 / 餐饮 / 今天', () async {
      final r = await nlu.parse('午饭20');
      expect(r.amount, equals(20.0));
      expect(r.categoryId, equals('cat.food'));
    });

    test('"刚才收工资15000" → 15000 / 工资 / 今天', () async {
      final r = await nlu.parse('刚才收工资15000');
      expect(r.amount, equals(15000.0));
      expect(r.categoryId, equals('cat.salary'));
    });

    test('"中午吃饭花了40" → 40 / 餐饮 / 今天', () async {
      final r = await nlu.parse('中午吃饭花了40');
      expect(r.amount, equals(40.0));
      expect(r.categoryId, equals('cat.food'));
    });

    test('"10月5号买咖啡7块" → 7 / 饮品 / 10-05', () async {
      final r = await nlu.parse('10月5号买咖啡7块');
      expect(r.amount, equals(7.0));
      expect(r.categoryId, equals('cat.drink'));
      expect(r.date?.month, equals(10));
      expect(r.date?.day, equals(5));
    });
  });
}
