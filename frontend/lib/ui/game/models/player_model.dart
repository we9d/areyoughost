class PlayerModel {
  final int number;
  final String name;
  final bool isAlive;

  PlayerModel({
    required this.number,
    required this.name,
    this.isAlive = true,
  });
}
