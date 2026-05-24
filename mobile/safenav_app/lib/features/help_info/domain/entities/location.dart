enum LocationCategory { faculty, library, cafeteria }

class Location {
  final String name;
  final LocationCategory category;

  const Location(this.name, this.category);

  static const all = [
    Location('faculty of engineering and technology', LocationCategory.faculty),
    Location('faculty of science', LocationCategory.faculty),
    Location('faculty of business and economics', LocationCategory.faculty),
    Location('faculty of arts', LocationCategory.faculty),
    Location('faculty of education', LocationCategory.faculty),
    Location('faculty of law and public administration', LocationCategory.faculty),
    Location('faculty of medicine', LocationCategory.faculty),
    Location('faculty of pharmacy nursing and health professions', LocationCategory.faculty),
    Location('faculty of art music and design', LocationCategory.faculty),
    Location('faculty of graduate studies', LocationCategory.faculty),
    Location('yusuf ahmed al ghanim library', LocationCategory.library),
    Location('main library', LocationCategory.library),
    Location('law library', LocationCategory.library),
    Location('nursing library', LocationCategory.library),
    Location('institute of women studies library', LocationCategory.library),
    Location('development studies library', LocationCategory.library),
    Location('main cafeteria', LocationCategory.cafeteria),
    Location('student cafeteria', LocationCategory.cafeteria),
    Location('science cafeteria', LocationCategory.cafeteria),
    Location('business cafeteria', LocationCategory.cafeteria),
    Location('arts cafeteria', LocationCategory.cafeteria),
    Location('nursing cafeteria', LocationCategory.cafeteria),
  ];
}
