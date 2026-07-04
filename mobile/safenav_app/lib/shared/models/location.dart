enum LocationCategory { faculty, library, cafeteria, landmark }

class Location {
  final String name;
  final LocationCategory category;
  final double latitude;
  final double longitude;

  const Location(this.name, this.category, this.latitude, this.longitude);

  static const all = [
    
    Location('faculty of engineering and information technology', LocationCategory.faculty, 31.96151396778399, 35.18432534944214),
    Location('faculty of engineering', LocationCategory.faculty, 31.959362, 35.181017),
    Location('faculty of science', LocationCategory.faculty, 31.958576, 35.181223),
    Location('faculty of business and economics', LocationCategory.faculty, 31.958480, 35.183226),
    Location('faculty of arts', LocationCategory.faculty, 31.960894, 35.182419),
    Location('faculty of education', LocationCategory.faculty, 31.960634, 35.183519),
    Location('faculty of law', LocationCategory.faculty, 31.959511, 35.182492),
    Location('faculty of health professions', LocationCategory.faculty, 31.961822, 35.183057),
    Location('faculty of media', LocationCategory.faculty, 31.961422, 35.183557),
    Location('faculty of sports', LocationCategory.faculty, 31.960801, 35.182126),
    Location('faculty of art and design', LocationCategory.faculty, 31.961962, 35.182081),
    Location('faculty of women studies', LocationCategory.faculty, 31.961099, 35.183218),
    Location('shawqi shaheen building', LocationCategory.faculty, 31.961302, 35.182330),
    Location('building for development studies', LocationCategory.faculty, 31.961146, 35.183536),
    Location('Al sadik', LocationCategory.faculty, 31.960226, 35.183019),

    
    Location('kamal nasir library', LocationCategory.library, 31.958983, 35.181994),
  
    
    
  ];
}
