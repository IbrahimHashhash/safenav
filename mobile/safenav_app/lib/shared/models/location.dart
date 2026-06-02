enum LocationCategory { faculty, library, cafeteria, landmark }

class Location {
  final String name;
  final LocationCategory category;
  final double latitude;
  final double longitude;

  const Location(this.name, this.category, this.latitude, this.longitude);

  static const all = [
    // Faculties
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
    Location('faculty of women studies', LocationCategory.faculty, 31.961099, 35.183218),
    Location('shawqi shaheen building', LocationCategory.faculty, 31.961302, 35.182330),
    Location('building for development studies', LocationCategory.faculty, 31.961146, 35.183536),

    // Libraries
    Location('kamal nasir library', LocationCategory.library, 31.958983, 35.181994),
    
    // Cafeterias
    Location('al sadik cafeteria', LocationCategory.cafeteria, 31.960226, 35.183019),
    
    // Landmarks
    Location('stairs masri', LocationCategory.landmark, 31.961105, 35.183914),
    Location('stairs khoury', LocationCategory.landmark, 31.961296, 35.183690),
    Location('stairs sport', LocationCategory.landmark, 31.960793, 35.182133),
    Location('stairs women studies 1', LocationCategory.landmark, 31.961310, 35.183459),
    Location('stairs women studies 2', LocationCategory.landmark, 31.961284, 35.183428),
    Location('stairs women studies 3', LocationCategory.landmark, 31.961178, 35.183195),
    Location('stairs women studies 4', LocationCategory.landmark, 31.961272, 35.183073),
    Location('corner a', LocationCategory.landmark, 31.959838, 35.182121),
    Location('corner b', LocationCategory.landmark, 31.959282, 35.181924),
    Location('corner c', LocationCategory.landmark, 31.959276, 35.182050),
    Location('corner d', LocationCategory.landmark, 31.959259, 35.181125),
    Location('corner e', LocationCategory.landmark, 31.961689, 35.183446),
    Location('corner f', LocationCategory.landmark, 31.961666, 35.183259),
    Location('corner g', LocationCategory.landmark, 31.961082, 35.182523),
  ];
}
