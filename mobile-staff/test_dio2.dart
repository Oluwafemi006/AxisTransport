import 'package:dio/dio.dart';

void main() {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000/api/v1'));
  // Create an interceptor to print the final URI
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    print(options.uri);
    handler.reject(DioException(requestOptions: options));
  }));
  dio.get('/client/locations/').catchError((e) => null);
  dio.get('client/locations/').catchError((e) => null);
}
