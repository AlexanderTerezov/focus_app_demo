class User {
  final int id;
  final String email;
  final String username;
  final int score;

  const User({
    required this.id,
    required this.email,
    required this.username,
    required this.score,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      username: json['username'] as String,
      score: json['score'] as int,
    );
  }
}
