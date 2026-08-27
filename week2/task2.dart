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
  
}