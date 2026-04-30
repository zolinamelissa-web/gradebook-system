class GradeEquivalency {
  final double minPercentage;
  final double maxPercentage;
  final double numericalGrade;
  final String? descriptor;

  const GradeEquivalency({
    required this.minPercentage,
    required this.maxPercentage,
    required this.numericalGrade,
    this.descriptor,
  });

  bool contains(double percentage) {
    return percentage >= minPercentage && percentage <= maxPercentage;
  }

  Map<String, dynamic> toJson() {
    return {
      'minPercentage': minPercentage,
      'maxPercentage': maxPercentage,
      'numericalGrade': numericalGrade,
      'descriptor': descriptor,
    };
  }

  factory GradeEquivalency.fromJson(Map<String, dynamic> json) {
    return GradeEquivalency(
      minPercentage: (json['minPercentage'] as num?)?.toDouble() ?? 0,
      maxPercentage: (json['maxPercentage'] as num?)?.toDouble() ?? 0,
      numericalGrade: (json['numericalGrade'] as num?)?.toDouble() ?? 0,
      descriptor: json['descriptor'] as String?,
    );
  }

  GradeEquivalency copyWith({
    double? minPercentage,
    double? maxPercentage,
    double? numericalGrade,
    String? descriptor,
  }) {
    return GradeEquivalency(
      minPercentage: minPercentage ?? this.minPercentage,
      maxPercentage: maxPercentage ?? this.maxPercentage,
      numericalGrade: numericalGrade ?? this.numericalGrade,
      descriptor: descriptor ?? this.descriptor,
    );
  }

  @override
  String toString() {
    return '${minPercentage.toStringAsFixed(0)}-${maxPercentage.toStringAsFixed(0)}% = ${numericalGrade.toStringAsFixed(2)}${descriptor != null ? ' ($descriptor)' : ''}';
  }
}

class GradeEquivalencyTable {
  final List<GradeEquivalency> equivalencies;

  const GradeEquivalencyTable({required this.equivalencies});

  static const depedTo1to5 = GradeEquivalencyTable(
    equivalencies: [
      GradeEquivalency(
        minPercentage: 97,
        maxPercentage: 100,
        numericalGrade: 1.00,
        descriptor: 'Excellent',
      ),
      GradeEquivalency(
        minPercentage: 94,
        maxPercentage: 96,
        numericalGrade: 1.25,
        descriptor: 'Excellent',
      ),
      GradeEquivalency(
        minPercentage: 91,
        maxPercentage: 93,
        numericalGrade: 1.50,
        descriptor: 'Very Good',
      ),
      GradeEquivalency(
        minPercentage: 88,
        maxPercentage: 90,
        numericalGrade: 1.75,
        descriptor: 'Very Good',
      ),
      GradeEquivalency(
        minPercentage: 85,
        maxPercentage: 87,
        numericalGrade: 2.00,
        descriptor: 'Good',
      ),
      GradeEquivalency(
        minPercentage: 82,
        maxPercentage: 84,
        numericalGrade: 2.25,
        descriptor: 'Good',
      ),
      GradeEquivalency(
        minPercentage: 79,
        maxPercentage: 81,
        numericalGrade: 2.50,
        descriptor: 'Satisfactory',
      ),
      GradeEquivalency(
        minPercentage: 76,
        maxPercentage: 78,
        numericalGrade: 2.75,
        descriptor: 'Satisfactory',
      ),
      GradeEquivalency(
        minPercentage: 75,
        maxPercentage: 75,
        numericalGrade: 3.00,
        descriptor: 'Passing',
      ),
      GradeEquivalency(
        minPercentage: 60,
        maxPercentage: 74,
        numericalGrade: 5.00,
        descriptor: 'Failed',
      ),
    ],
  );

  static const depedTo4point0 = GradeEquivalencyTable(
    equivalencies: [
      GradeEquivalency(
        minPercentage: 97,
        maxPercentage: 100,
        numericalGrade: 4.00,
        descriptor: 'Excellent',
      ),
      GradeEquivalency(
        minPercentage: 94,
        maxPercentage: 96,
        numericalGrade: 3.75,
        descriptor: 'Excellent',
      ),
      GradeEquivalency(
        minPercentage: 91,
        maxPercentage: 93,
        numericalGrade: 3.50,
        descriptor: 'Very Good',
      ),
      GradeEquivalency(
        minPercentage: 88,
        maxPercentage: 90,
        numericalGrade: 3.25,
        descriptor: 'Very Good',
      ),
      GradeEquivalency(
        minPercentage: 85,
        maxPercentage: 87,
        numericalGrade: 3.00,
        descriptor: 'Good',
      ),
      GradeEquivalency(
        minPercentage: 82,
        maxPercentage: 84,
        numericalGrade: 2.75,
        descriptor: 'Good',
      ),
      GradeEquivalency(
        minPercentage: 79,
        maxPercentage: 81,
        numericalGrade: 2.50,
        descriptor: 'Satisfactory',
      ),
      GradeEquivalency(
        minPercentage: 76,
        maxPercentage: 78,
        numericalGrade: 2.25,
        descriptor: 'Satisfactory',
      ),
      GradeEquivalency(
        minPercentage: 75,
        maxPercentage: 75,
        numericalGrade: 2.00,
        descriptor: 'Passing',
      ),
      GradeEquivalency(
        minPercentage: 60,
        maxPercentage: 74,
        numericalGrade: 0.00,
        descriptor: 'Failed',
      ),
    ],
  );

  static const List<GradeEquivalencyTable> presets = [
    depedTo1to5,
    depedTo4point0,
  ];

  double? convertPercentageToNumerical(double percentage) {
    for (final equiv in equivalencies) {
      if (equiv.contains(percentage)) {
        return equiv.numericalGrade;
      }
    }

    final floored = percentage.floorToDouble();
    if (floored != percentage) {
      for (final equiv in equivalencies) {
        if (equiv.contains(floored)) {
          return equiv.numericalGrade;
        }
      }
    }
    return null;
  }

  String? getDescriptor(double percentage) {
    for (final equiv in equivalencies) {
      if (equiv.contains(percentage)) {
        return equiv.descriptor;
      }
    }

    final floored = percentage.floorToDouble();
    if (floored != percentage) {
      for (final equiv in equivalencies) {
        if (equiv.contains(floored)) {
          return equiv.descriptor;
        }
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {'equivalencies': equivalencies.map((e) => e.toJson()).toList()};
  }

  factory GradeEquivalencyTable.fromJson(Map<String, dynamic> json) {
    final equivList = json['equivalencies'] as List<dynamic>? ?? [];
    return GradeEquivalencyTable(
      equivalencies: equivList
          .map((e) => GradeEquivalency.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  GradeEquivalencyTable copyWith({List<GradeEquivalency>? equivalencies}) {
    return GradeEquivalencyTable(
      equivalencies: equivalencies ?? this.equivalencies,
    );
  }

  bool get isEmpty => equivalencies.isEmpty;
  bool get isNotEmpty => equivalencies.isNotEmpty;
}
