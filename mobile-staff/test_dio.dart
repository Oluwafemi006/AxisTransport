import 'package:dio/dio.dart';

void main() {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000/api/v1'));
  print(dio.options.baseUrl);
  final uri = Uri.parse(dio.options.baseUrl).resolve('/client/locations/');
  print(uri);
}
