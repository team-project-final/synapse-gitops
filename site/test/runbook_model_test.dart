import 'package:flutter_test/flutter_test.dart';
import 'package:synapse_runbooks/models/runbook.dart';

void main() {
  group('Runbook model', () {
    test('fromJson parses correctly', () {
      final json = {
        'slug': 'step1-aws-account-setup',
        'title': 'AWS 계정 초기 설정 (Step 1 상세)',
        'metadata': {
          '대상': 'AWS 콘솔/CLI 사용 경험이 적은 작업자',
          '소요 시간': '약 25분',
          '결과': 'aws sts get-caller-identity가 응답',
        },
        'category': 'steps',
        'order': 1,
        'body': '## 내용\n\n본문입니다.',
      };

      final runbook = Runbook.fromJson(json);

      expect(runbook.slug, 'step1-aws-account-setup');
      expect(runbook.title, 'AWS 계정 초기 설정 (Step 1 상세)');
      expect(runbook.category, RunbookCategory.steps);
      expect(runbook.order, 1);
      expect(runbook.target, 'AWS 콘솔/CLI 사용 경험이 적은 작업자');
      expect(runbook.duration, '약 25분');
      expect(runbook.body, '## 내용\n\n본문입니다.');
    });

    test('fromJson handles missing metadata gracefully', () {
      final json = {
        'slug': 'test',
        'title': 'Test',
        'metadata': <String, dynamic>{},
        'category': 'onboarding',
        'order': 0,
        'body': 'body',
      };

      final runbook = Runbook.fromJson(json);
      expect(runbook.target, isNull);
      expect(runbook.duration, isNull);
    });

    test('RunbookIndex fromJson parses without body', () {
      final json = {
        'slug': 'step1-aws-account-setup',
        'title': 'AWS 계정 초기 설정',
        'metadata': {'대상': '작업자', '소요 시간': '25분'},
        'category': 'steps',
        'order': 1,
      };

      final index = RunbookIndex.fromJson(json);
      expect(index.slug, 'step1-aws-account-setup');
      expect(index.title, 'AWS 계정 초기 설정');
      expect(index.category, RunbookCategory.steps);
    });
  });
}
