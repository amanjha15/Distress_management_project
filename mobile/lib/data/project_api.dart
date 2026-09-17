import 'dart:convert';

import 'package:http/http.dart' as http;

import 'custom_http_client.dart';
import 'live_detection_api.dart' show kApiV1;

/// Matches backend `ProjectResponse` (app/schemas/project.py). A Project is
/// the container every module (M1-M4) operates within.
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.ownerId,
    this.description,
    this.highwayName,
    this.highwayNumber,
    this.startingChainage,
    this.endingChainage,
    this.state,
    this.memberEmails = const [],
  });

  final int id;
  final String name;
  final int ownerId;
  final String? description;
  final String? highwayName;
  final String? highwayNumber;
  final String? startingChainage;
  final String? endingChainage;
  final String? state;
  final List<String> memberEmails;

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as int,
      name: json['name'] as String,
      ownerId: json['owner_id'] as int,
      description: json['description'] as String?,
      highwayName: json['highway_name'] as String?,
      highwayNumber: json['highway_number'] as String?,
      startingChainage: json['starting_chainage'] as String?,
      endingChainage: json['ending_chainage'] as String?,
      state: json['state'] as String?,
      memberEmails: (json['member_emails'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }
}

class ProjectApiException implements Exception {
  const ProjectApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Talks to the new role-scoped `/projects` routes (app/api/v1/routes/
/// projects.py) -- admins see every project, employees only the ones
/// they're a member of.
class ProjectApi {
  ProjectApi(this.token);

  final String token;
  final http.Client _client = CustomHttpClient();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<List<Project>> listProjects() async {
    final response = await _client.get(Uri.parse('$kApiV1/projects/'), headers: _headers);
    if (response.statusCode != 200) {
      throw const ProjectApiException('Failed to load projects.');
    }
    final body = jsonDecode(response.body) as List<dynamic>;
    return body.map((e) => Project.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Project> createProject({
    required String name,
    String? description,
    String? highwayName,
    String? highwayNumber,
    String? startingChainage,
    String? endingChainage,
    String? state,
    List<String> memberEmails = const [],
  }) async {
    final response = await _client.post(
      Uri.parse('$kApiV1/projects/'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'description': description,
        'highway_name': highwayName,
        'highway_number': highwayNumber,
        'starting_chainage': startingChainage,
        'ending_chainage': endingChainage,
        'state': state,
        'member_emails': memberEmails,
      }),
    );
    if (response.statusCode != 201) {
      throw const ProjectApiException('Failed to create project.');
    }
    return Project.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
