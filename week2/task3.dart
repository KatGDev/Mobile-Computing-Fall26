class Student {
  // fields: name, id, grades
  String name;
  int id;
  List<double> grades;

  // constructor
  Student(this.name, this.id, this.grades);

  double calculateGPA() {
    return grades.reduce((a, b) => a + b) / grades.length;
  }
}

void main() {
  var students = [
    Student('Sahar', 1, [3.8, 4.0, 3.6]),
    Student('Alex', 2, [3.2, 3.5, 3.9]),
  ];

  for (var s in students) {
    print('${s.name}: ${s.calculateGPA()}');
  }
}