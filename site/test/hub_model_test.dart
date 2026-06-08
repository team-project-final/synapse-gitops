import 'package:flutter_test/flutter_test.dart';
import 'package:synapse_runbooks/models/hub.dart';

void main() {
  group('HubData model', () {
    test('fromJson 파싱', () {
      final json = {
        'title': 'Synapse 통합 핸드오프 허브',
        'lastUpdated': '2026-06-08',
        'envs': ['로컬 compose', 'dev (EKS)', 'staging', 'prod'],
        'statusTable': [
          {
            'service': 'platform-svc',
            'cells': [
              {'env': '로컬 compose', 'status': 'healthy', 'label': 'Healthy'},
              {'env': 'prod', 'status': 'planned', 'label': 'W5'},
            ],
          },
        ],
        'bodyMarkdown': '# 제목\n\n본문',
      };

      final hub = HubData.fromJson(json);

      expect(hub.title, 'Synapse 통합 핸드오프 허브');
      expect(hub.lastUpdated, '2026-06-08');
      expect(hub.envs.length, 4);
      expect(hub.statusTable.length, 1);
      expect(hub.statusTable[0].service, 'platform-svc');
      expect(hub.statusTable[0].cells[0].status, 'healthy');
      expect(hub.statusTable[0].cells[1].label, 'W5');
      expect(hub.bodyMarkdown, contains('본문'));
    });

    test('빈 statusTable 처리', () {
      final hub = HubData.fromJson({
        'title': 'T',
        'lastUpdated': '',
        'envs': [],
        'statusTable': [],
        'bodyMarkdown': 'x',
      });
      expect(hub.statusTable, isEmpty);
      expect(hub.envs, isEmpty);
    });

    test('누락 필드 graceful 기본값', () {
      final hub = HubData.fromJson({'bodyMarkdown': 'only body'});
      expect(hub.title, 'Handoff Hub');
      expect(hub.statusTable, isEmpty);
      expect(hub.bodyMarkdown, 'only body');
    });
  });
}
