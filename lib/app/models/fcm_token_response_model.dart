class FcmTokenResponseModel {
  final String message;

  FcmTokenResponseModel({
    required this.message,
  });

  factory FcmTokenResponseModel.fromJson(Map<String, dynamic> json) {
    return FcmTokenResponseModel(
      message: json['message'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message': message,
    };
  }
}