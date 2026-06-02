enum LocationCategory { faculty, library, cafeteria }

class Location {
  final String name;
  final LocationCategory category;
  final double latitude;
  final double longitude;

  const Location(this.name, this.category, this.latitude, this.longitude);

  static const all = [
    Location('faculty of engineering and information technology', LocationCategory.faculty, 31.96151396778399, 35.18432534944214),
    Location('faculty of engineering', LocationCategory.faculty, 31.959362, 35.181017),
    Location('faculty of science', LocationCategory.faculty, 31.958465, 35.181178),
    Location('faculty of business and economics', LocationCategory.faculty, 31.958419, 35.183264),
    Location('faculty of arts', LocationCategory.faculty, 31.960842, 35.182567),
    Location('faculty of education', LocationCategory.faculty, 31.960634, 35.183564),
    Location('faculty of law', LocationCategory.faculty, 31.959511, 35.182492),
    Location('faculty of health professions', LocationCategory.faculty, 31.961984, 35.182885),
    Location('faculty of media', LocationCategory.faculty, 31.961422, 35.183557),
    Location('faculty of sports', LocationCategory.faculty, 31.960801, 35.182126),
    Location('faculty of art and design', LocationCategory.faculty, 31.961962, 35.182081),
    Location('yusuf ahmed al ghanim library', LocationCategory.library, 31.958983, 35.181994),
    Location('main cafeteria', LocationCategory.cafeteria, 31.960226, 35.183019),
  ];
}
