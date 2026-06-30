import 'package:flutter/material.dart';

/// Dart mirror of diagnostic_system/schemas.py.
/// Keep field names/types in sync with the Pydantic models on the backend.
/// Confirmed against a real streamQuery response: the final SSE event's
/// content.parts[].text field contains this JSON as a string.

class TriageResults {
  final int totalImagesAnalyzed;
  final int irrelevantImagesDiscarded;
  final bool logicalConsistencyCheck;

  TriageResults({
    required this.totalImagesAnalyzed,
    required this.irrelevantImagesDiscarded,
    required this.logicalConsistencyCheck,
  });

  factory TriageResults.fromJson(Map<String, dynamic> json) => TriageResults(
        totalImagesAnalyzed: json['total_images_analyzed'] ?? 0,
        irrelevantImagesDiscarded: json['irrelevant_images_discarded'] ?? 0,
        logicalConsistencyCheck: json['logical_consistency_check'] ?? false,
      );
}

class IssueCategorization {
  final String category;
  final String? subcategory;
  final String mediaTypeAnalyzed;
  final String visualEvidenceSummary;
  final bool descriptionAlignment;
  final double confidence;

  IssueCategorization({
    required this.category,
    this.subcategory,
    required this.mediaTypeAnalyzed,
    required this.visualEvidenceSummary,
    required this.descriptionAlignment,
    required this.confidence,
  });

  factory IssueCategorization.fromJson(Map<String, dynamic> json) =>
      IssueCategorization(
        category: json['category'] ?? 'Other',
        subcategory: json['subcategory'],
        mediaTypeAnalyzed: json['media_type_analyzed'] ?? 'image',
        visualEvidenceSummary: json['visual_evidence_summary'] ?? '',
        descriptionAlignment: json['description_alignment'] ?? false,
        confidence: (json['confidence'] ?? 0.0).toDouble(),
      );

  /// Tag color keyed off category, matching the Literal values in schemas.py.
  Color get color {
    switch (category) {
      case 'Pothole':
        return const Color(0xFFD32F2F); // red 700
      case 'Garbage/Sanitation':
        return const Color(0xFF8D6E63); // brown 400
      case 'Water Leakage':
        return const Color(0xFF1976D2); // blue 700
      case 'Sewage/Drainage':
        return const Color(0xFF6A1B9A); // purple 800
      case 'Streetlight/Electrical':
        return const Color(0xFFF9A825); // yellow 800
      case 'Road Damage':
        return const Color(0xFFEF6C00); // orange 800
      case 'Illegal Dumping':
        return const Color(0xFFE65100); // deep orange 900
      case 'Fallen Tree/Debris':
        return const Color(0xFF2E7D32); // green 800
      case 'Construction Hazard':
        return const Color(0xFFF57F17); // amber 900
      default:
        return const Color(0xFF616161); // grey 700
    }
  }

  IconData get icon {
    switch (category) {
      case 'Pothole':
      case 'Road Damage':
        return Icons.warning_amber_rounded;
      case 'Garbage/Sanitation':
      case 'Illegal Dumping':
        return Icons.delete_outline;
      case 'Water Leakage':
        return Icons.water_drop_outlined;
      case 'Sewage/Drainage':
        return Icons.plumbing;
      case 'Streetlight/Electrical':
        return Icons.lightbulb_outline;
      case 'Fallen Tree/Debris':
        return Icons.park_outlined;
      case 'Construction Hazard':
        return Icons.construction;
      default:
        return Icons.report_problem_outlined;
    }
  }
}

class VerifiedAnalysis {
  final String issueType;
  final String progressionTimeline;
  final String rootCause;
  final String causeCategory;

  VerifiedAnalysis({
    required this.issueType,
    required this.progressionTimeline,
    required this.rootCause,
    required this.causeCategory,
  });

  factory VerifiedAnalysis.fromJson(Map<String, dynamic> json) =>
      VerifiedAnalysis(
        issueType: json['issue_type'] ?? '',
        progressionTimeline: json['progression_timeline'] ?? '',
        rootCause: json['root_cause'] ?? '',
        causeCategory: json['cause_category'] ?? '',
      );
}

class RiskAssessment {
  final int riskScore;
  final List<String> riskFactors;
  final String recommendation;

  RiskAssessment({
    required this.riskScore,
    required this.riskFactors,
    required this.recommendation,
  });

  factory RiskAssessment.fromJson(Map<String, dynamic> json) =>
      RiskAssessment(
        riskScore: json['risk_score'] ?? 0,
        riskFactors: List<String>.from(json['risk_factors'] ?? const []),
        recommendation: json['recommendation'] ?? '',
      );

  /// Color-coded by score, used on the risk badge.
  Color get color {
    if (riskScore >= 70) return const Color(0xFFD32F2F); // red 700
    if (riskScore >= 40) return const Color(0xFFEF6C00); // orange 800
    return const Color(0xFF2E7D32); // green 800
  }
}

class VerificationOutput {
  final TriageResults triageResults;
  final List<String> clarifyingQuestions;
  final IssueCategorization? issueCategorization;
  final VerifiedAnalysis? verifiedAnalysis;
  final List<String> contextualFactors;
  final RiskAssessment? riskAssessment;

  VerificationOutput({
    required this.triageResults,
    required this.clarifyingQuestions,
    this.issueCategorization,
    this.verifiedAnalysis,
    required this.contextualFactors,
    this.riskAssessment,
  });

  /// True if the agent needs more info before it can finish categorizing.
  bool get needsClarification => clarifyingQuestions.isNotEmpty;

  factory VerificationOutput.fromJson(Map<String, dynamic> json) =>
      VerificationOutput(
        triageResults: TriageResults.fromJson(json['triage_results'] ?? {}),
        clarifyingQuestions:
            List<String>.from(json['clarifying_questions'] ?? const []),
        issueCategorization: json['issue_categorization'] != null
            ? IssueCategorization.fromJson(json['issue_categorization'])
            : null,
        verifiedAnalysis: json['verified_analysis'] != null
            ? VerifiedAnalysis.fromJson(json['verified_analysis'])
            : null,
        contextualFactors:
            List<String>.from(json['contextual_factors'] ?? const []),
        riskAssessment: json['risk_assessment'] != null
            ? RiskAssessment.fromJson(json['risk_assessment'])
            : null,
      );
}
