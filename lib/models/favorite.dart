class Favorite {
  String url;
  String title;

  Favorite({required this.url, required this.title});

  factory Favorite.fromJson(Map<String, dynamic> json) => Favorite(
    url: json['url'],
    title: json['title'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
  };
}
