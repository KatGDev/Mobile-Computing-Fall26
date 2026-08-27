double average(List<int> values) {
  double total = 0; 
  for (var v in values) {
    total += v;
  }
  return total / values.length;
}

void main() {
  print(average([10, 20, 30])); // should print 20.0
}