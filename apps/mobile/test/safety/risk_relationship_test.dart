import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/safety/message_risk.dart';
import 'package:veil_mobile/src/features/safety/application/relationship.dart';
import 'package:veil_mobile/src/features/safety/application/risk_relationship.dart';

void main() {
  test('each relationship maps to the checker case of the same name, and a new contact is unknown', () {
    expect({for (final r in Relationship.values) r: riskRelationshipOf(r)}, {
      Relationship.verified: RiskRelationship.verified,
      Relationship.saved: RiskRelationship.saved,
      Relationship.known: RiskRelationship.known,
      Relationship.newContact: RiskRelationship.unknown,
      Relationship.changed: RiskRelationship.changed,
    });
    expect(Relationship.values.map(riskRelationshipOf).toSet(), RiskRelationship.values.toSet(),
        reason: 'every checker case is reachable');
  });
}
