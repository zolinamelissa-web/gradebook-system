import 'dart:io';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class LessonAIService {
  // Use a free Gemini API key - users should replace with their own
  static const String _apiKey = 'AIzaSyDe84cmQ-EV70RoXSV69EO5tr4LtW4pSpA';

  /// Extract text from PDF file
  static Future<String> extractTextFromPDF(String pdfPath) async {
    try {
      print('[LessonAIService] Extracting text from PDF: $pdfPath');
      final file = File(pdfPath);

      if (!await file.exists()) {
        throw Exception('PDF file not found at path: $pdfPath');
      }

      final bytes = await file.readAsBytes();
      final document = PdfDocument(inputBytes: bytes);

      final textExtractor = PdfTextExtractor(document);
      final text = textExtractor.extractText();

      document.dispose();

      print('[LessonAIService] Extracted ${text.length} characters from PDF');
      return text;
    } catch (e) {
      print('[LessonAIService] Error extracting PDF text: $e');
      rethrow;
    }
  }

  /// Extract text from either PDF or DOCX based on file extension.
  /// For DOCX we send base64 to Gemini and let the model extract visible text.
  static Future<String> extractTextFromLessonFile(String path) async {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) {
      return extractTextFromPDF(path);
    } else if (lower.endsWith('.docx')) {
      final file = File(path);
      if (!await file.exists()) {
        throw Exception('DOCX file not found at path: $path');
      }
      final bytes = await file.readAsBytes();
      final base64Data = base64Encode(bytes);
      // Use a special marker understood by generateLessonContent
      return 'DOCX_FILE_BASE64::$base64Data';
    } else {
      throw Exception('Unsupported file type. Please use PDF or DOCX.');
    }
  }

  /// Generate lesson content with AI using extracted PDF text
  static Future<LessonAIResult> generateLessonContent({
    required String pdfText,
    required String lessonTitle,
    required int weekNumber,
  }) async {
    try {
      print('[LessonAIService] Generating lesson content with AI...');

      if (_apiKey == 'YOUR_GEMINI_API_KEY_HERE') {
        print(
          '[LessonAIService] Warning: Using placeholder API key. Please set a valid Gemini API key.',
        );
        // Return mock data for testing without API key
        return _generateMockContent(pdfText, lessonTitle, weekNumber);
      }

      final model = GenerativeModel(
        model: 'gemini-1.5-flash-latest',
        apiKey: _apiKey,
      );

      String materialSection;

      if (pdfText.startsWith('DOCX_FILE_BASE64::')) {
        final base64Data = pdfText.substring('DOCX_FILE_BASE64::'.length);
        materialSection =
            '''
The attached lesson material is a Microsoft Word (.docx) file provided as base64:

$base64Data

You MUST:
- Decode the DOCX
- Extract only the visible human-readable text (ignore binary, XML, or formatting)
- Use that extracted text as the lesson material.
''';
      } else {
        materialSection =
            '''
Lesson Material:
$pdfText
''';
      }

      final prompt =
          '''
Analyze the following lesson material and provide clean, formatted educational content.

Lesson Title: $lessonTitle
Week Number: $weekNumber

$materialSection

Provide your response in EXACTLY this format:

===CONTENT===
Write a well-structured summary organized into clear paragraphs. Use proper paragraph breaks (double line breaks) between sections. Include headings where appropriate. Make it readable and professional. Do NOT include any notes, disclaimers, or meta-commentary.

===OBJECTIVES===
Create 3-5 complete learning objectives as full sentences. Each objective should follow the ABCD format (Audience, Behavior, Condition, Degree) but written as a natural, flowing sentence. For example:
"Students will be able to explain the core concepts with 80% accuracy after completing the lesson and exercises."

Write each objective as a complete sentence on its own line. Do NOT use labels like "Objective 1:" or "Audience:", "Behavior:", etc. Just write clean, professional learning objective sentences.

===REFERENCES===
List references, citations, or sources found in the material. If none exist, suggest 3-5 relevant academic resources. Format as a simple numbered list. Do NOT include any notes or disclaimers.
''';

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);

      if (response.text == null || response.text!.isEmpty) {
        throw Exception('AI returned empty response');
      }

      final result = _parseAIResponse(response.text!);
      print('[LessonAIService] AI generation completed successfully');
      return result;
    } catch (e) {
      print('[LessonAIService] Error generating lesson content: $e');
      // Fallback to mock data if AI fails
      return _generateMockContent(pdfText, lessonTitle, weekNumber);
    }
  }

  /// Parse AI response into structured data
  static LessonAIResult _parseAIResponse(String response) {
    try {
      final contentMatch = RegExp(
        r'===CONTENT===(.*?)===OBJECTIVES===',
        dotAll: true,
      ).firstMatch(response);
      final objectivesMatch = RegExp(
        r'===OBJECTIVES===(.*?)===REFERENCES===',
        dotAll: true,
      ).firstMatch(response);
      final referencesMatch = RegExp(
        r'===REFERENCES===(.*?)$',
        dotAll: true,
      ).firstMatch(response);

      var content = contentMatch?.group(1)?.trim() ?? 'Content not available';
      var objectives =
          objectivesMatch?.group(1)?.trim() ?? 'Objectives not available';
      var references =
          referencesMatch?.group(1)?.trim() ?? 'References not available';

      // Clean up AI metadata and notes
      content = _cleanAIOutput(content);
      objectives = _cleanAIOutput(objectives);
      references = _cleanAIOutput(references);

      return LessonAIResult(
        content: content,
        objectives: objectives,
        references: references,
      );
    } catch (e) {
      print('[LessonAIService] Error parsing AI response: $e');
      return LessonAIResult(
        content: response,
        objectives: 'Error parsing objectives',
        references: 'Error parsing references',
      );
    }
  }

  /// Clean AI output by removing metadata, notes, disclaimers, and institutional headers
  static String _cleanAIOutput(String text) {
    // Remove common AI disclaimers and notes
    var cleaned = text;

    // Remove lines starting with "Note:", "*Note:", "Disclaimer:", etc.
    cleaned = cleaned.replaceAll(RegExp(r'^\*?Note:.*$', multiLine: true), '');
    cleaned = cleaned.replaceAll(
      RegExp(r'^\*?Disclaimer:.*$', multiLine: true),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'^\*?\(Note:.*\)\*?$', multiLine: true),
      '',
    );

    // Remove phrases like "This is auto-generated", "AI-generated", etc.
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\*?This is (auto-generated|AI-generated).*?\*?',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\*?Configure.*?API key.*?\*?', caseSensitive: false),
      '',
    );

    // Remove institutional headers (school names, addresses, etc.)
    cleaned = _removeInstitutionalHeaders(cleaned);

    // Remove excessive blank lines (more than 2 consecutive)
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return cleaned.trim();
  }

  /// Remove institutional headers like school names, addresses from content
  static String _removeInstitutionalHeaders(String text) {
    final lines = text.split('\n');
    final cleanedLines = <String>[];
    bool inHeader = true;

    for (final line in lines) {
      final trimmed = line.trim();

      // Skip empty lines at the start
      if (inHeader && trimmed.isEmpty) continue;

      // Check if line looks like a header (institutional info)
      if (inHeader) {
        // Skip lines that are:
        // - All uppercase with common institutional keywords
        // - Contain address-like patterns
        // - Are mostly underscores or dashes
        final isAllCaps =
            trimmed == trimmed.toUpperCase() &&
            trimmed.length > 5 &&
            RegExp(r'[A-Z]').hasMatch(trimmed);
        final hasInstitutionalKeywords = RegExp(
          r'(INSTITUTE|UNIVERSITY|COLLEGE|SCHOOL|ACADEMY|DEPARTMENT|FACULTY|CAMPUS|NATIONAL|HIGHWAY|STREET|ROAD|CITY|PROVINCE)',
          caseSensitive: false,
        ).hasMatch(trimmed);
        final isUnderscoreLine = RegExp(r'^[_\-\s]{10,}$').hasMatch(trimmed);

        if (isAllCaps || hasInstitutionalKeywords || isUnderscoreLine) {
          continue; // Skip this header line
        }

        // If we hit a markdown header or substantial content, stop skipping
        if (trimmed.startsWith('#') ||
            (trimmed.length > 20 && !isAllCaps && !hasInstitutionalKeywords)) {
          inHeader = false;
        }
      }

      // Add the line if we're past the header
      if (!inHeader) {
        cleanedLines.add(line);
      }
    }

    return cleanedLines.join('\n');
  }

  /// Generate mock content for testing without API key
  static LessonAIResult _generateMockContent(
    String pdfText,
    String lessonTitle,
    int weekNumber,
  ) {
    print('[LessonAIService] Generating mock content (no API key configured)');

    final contentPreview = pdfText.length > 500
        ? '${pdfText.substring(0, 500)}...'
        : pdfText;

    return LessonAIResult(
      content:
          '''
# $lessonTitle

## Overview

${contentPreview.isNotEmpty ? contentPreview : 'This lesson covers important concepts and practical applications. Students will explore fundamental principles and their real-world applications through interactive examples and case studies.'}

## Key Concepts

The lesson introduces core theoretical frameworks and demonstrates their practical utility. Students will engage with material through structured activities designed to build comprehension and analytical skills.

## Application

Practical exercises allow students to apply learned concepts to realistic scenarios, fostering critical thinking and problem-solving abilities essential for academic and professional success.
''',
      objectives: '''
Students will be able to explain and apply the core concepts with 80% accuracy after completing the lesson and exercises.

Students will be able to analyze and evaluate practical scenarios using the knowledge gained from this lesson, demonstrating critical thinking skills.

Students will be able to create solutions to real-world problems by working individually or in groups, meeting the specified criteria and standards.
''',
      references:
          '''
1. Course textbook - Chapter related to $lessonTitle
2. Academic journals on the subject matter
3. Online educational resources and tutorials
4. Industry publications and case studies
5. Supplementary reading materials provided in class
''',
    );
  }
}

/// Result from AI lesson content generation
class LessonAIResult {
  final String content;
  final String objectives;
  final String references;

  LessonAIResult({
    required this.content,
    required this.objectives,
    required this.references,
  });
}
