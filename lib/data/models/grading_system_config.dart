enum GradingSystemType {
  depedPercentage,
  college1to5,
  college4point0,
  percentage100,
  custom,
}

class GradingSystemConfig {
  final GradingSystemType type;
  final String displayName;
  final double minScore;
  final double maxScore;
  final double passingScore;
  final bool useTransmutation;
  final double? transmutationBase;

  const GradingSystemConfig({
    required this.type,
    required this.displayName,
    required this.minScore,
    required this.maxScore,
    required this.passingScore,
    this.useTransmutation = false,
    this.transmutationBase,
  });

  static const depedPercentage = GradingSystemConfig(
    type: GradingSystemType.depedPercentage,
    displayName: 'DepEd K-12 (60-100%, transmuted to 75)',
    minScore: 60,
    maxScore: 100,
    passingScore: 75,
    useTransmutation: true,
    transmutationBase: 60,
  );

  static const college1to5 = GradingSystemConfig(
    type: GradingSystemType.college1to5,
    displayName: 'College (1.00-5.00, 1.00 highest)',
    minScore: 1.00,
    maxScore: 5.00,
    passingScore: 3.00,
    useTransmutation: false,
  );

  static const college4point0 = GradingSystemConfig(
    type: GradingSystemType.college4point0,
    displayName: 'College (4.0 scale, 4.0 highest)',
    minScore: 0.0,
    maxScore: 4.0,
    passingScore: 1.0,
    useTransmutation: false,
  );

  static const percentage100 = GradingSystemConfig(
    type: GradingSystemType.percentage100,
    displayName: 'Percentage (0-100%, zero-based)',
    minScore: 0,
    maxScore: 100,
    passingScore: 60,
    useTransmutation: false,
  );

  static List<GradingSystemConfig> get presets => [
        depedPercentage,
        college1to5,
        college4point0,
        percentage100,
      ];

  static GradingSystemConfig fromType(GradingSystemType type) {
    switch (type) {
      case GradingSystemType.depedPercentage:
        return depedPercentage;
      case GradingSystemType.college1to5:
        return college1to5;
      case GradingSystemType.college4point0:
        return college4point0;
      case GradingSystemType.percentage100:
        return percentage100;
      case GradingSystemType.custom:
        return percentage100;
    }
  }

  static GradingSystemType typeFromString(String value) {
    switch (value) {
      case 'depedPercentage':
        return GradingSystemType.depedPercentage;
      case 'college1to5':
        return GradingSystemType.college1to5;
      case 'college4point0':
        return GradingSystemType.college4point0;
      case 'percentage100':
        return GradingSystemType.percentage100;
      case 'custom':
        return GradingSystemType.custom;
      default:
        return GradingSystemType.percentage100;
    }
  }

  String get typeString {
    switch (type) {
      case GradingSystemType.depedPercentage:
        return 'depedPercentage';
      case GradingSystemType.college1to5:
        return 'college1to5';
      case GradingSystemType.college4point0:
        return 'college4point0';
      case GradingSystemType.percentage100:
        return 'percentage100';
      case GradingSystemType.custom:
        return 'custom';
    }
  }

  double transmute(double rawScore) {
    if (!useTransmutation || transmutationBase == null) {
      return rawScore;
    }

    if (rawScore < transmutationBase!) {
      return minScore;
    }

    final range = maxScore - passingScore;
    final rawRange = maxScore - transmutationBase!;
    final normalized = (rawScore - transmutationBase!) / rawRange;
    return passingScore + (normalized * range);
  }

  String formatGrade(double score) {
    final transmuted = transmute(score);
    
    if (type == GradingSystemType.college1to5 || type == GradingSystemType.college4point0) {
      return transmuted.toStringAsFixed(2);
    }
    
    return transmuted.toStringAsFixed(1);
  }

  bool isPassing(double score) {
    final transmuted = transmute(score);
    
    if (type == GradingSystemType.college1to5) {
      return transmuted <= passingScore;
    }
    
    return transmuted >= passingScore;
  }

  Map<String, dynamic> toJson() {
    return {
      'type': typeString,
      'displayName': displayName,
      'minScore': minScore,
      'maxScore': maxScore,
      'passingScore': passingScore,
      'useTransmutation': useTransmutation,
      'transmutationBase': transmutationBase,
    };
  }

  factory GradingSystemConfig.fromJson(Map<String, dynamic> json) {
    return GradingSystemConfig(
      type: typeFromString(json['type'] as String? ?? 'percentage100'),
      displayName: json['displayName'] as String? ?? 'Percentage (0-100%)',
      minScore: (json['minScore'] as num?)?.toDouble() ?? 0,
      maxScore: (json['maxScore'] as num?)?.toDouble() ?? 100,
      passingScore: (json['passingScore'] as num?)?.toDouble() ?? 60,
      useTransmutation: json['useTransmutation'] as bool? ?? false,
      transmutationBase: (json['transmutationBase'] as num?)?.toDouble(),
    );
  }

  GradingSystemConfig copyWith({
    GradingSystemType? type,
    String? displayName,
    double? minScore,
    double? maxScore,
    double? passingScore,
    bool? useTransmutation,
    double? transmutationBase,
  }) {
    return GradingSystemConfig(
      type: type ?? this.type,
      displayName: displayName ?? this.displayName,
      minScore: minScore ?? this.minScore,
      maxScore: maxScore ?? this.maxScore,
      passingScore: passingScore ?? this.passingScore,
      useTransmutation: useTransmutation ?? this.useTransmutation,
      transmutationBase: transmutationBase ?? this.transmutationBase,
    );
  }
}
