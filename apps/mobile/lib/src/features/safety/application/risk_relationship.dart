import '../../../core/safety/message_risk.dart';
import 'relationship.dart';

/// The checker's view of who sent a message. The trust layer's
/// [Relationship] and the checker's [RiskRelationship] name the same five
/// cases; the checker lives in core and cannot import the trust layer.
RiskRelationship riskRelationshipOf(Relationship relationship) => switch (relationship) {
      Relationship.verified => RiskRelationship.verified,
      Relationship.saved => RiskRelationship.saved,
      Relationship.known => RiskRelationship.known,
      Relationship.newContact => RiskRelationship.unknown,
      Relationship.changed => RiskRelationship.changed,
    };
