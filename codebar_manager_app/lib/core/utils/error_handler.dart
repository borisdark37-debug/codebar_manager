import 'package:dio/dio.dart';

/// Transforme les erreurs techniques en messages lisibles pour l'utilisateur.
class AppErrorHandler {
  static String friendly(Object error) {
    if (error is DioException) {
      return _fromDio(error);
    }
    final msg = error.toString();
    if (msg.contains('SocketException') ||
        msg.contains('Connection refused') ||
        msg.contains('Network is unreachable')) {
      return 'Impossible de joindre le serveur. Vérifiez votre connexion internet.';
    }
    if (msg.contains('TimeoutException') || msg.contains('timeout')) {
      return 'Le serveur met trop de temps à répondre. Réessayez dans un instant.';
    }
    if (msg.contains('Session expirée') || msg.contains('Unauthenticated')) {
      return 'Votre session a expiré. Veuillez vous reconnecter.';
    }
    // Message générique non-effrayant
    return 'Une erreur est survenue. Veuillez réessayer ou contacter le support.';
  }

  static String _fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'La connexion au serveur a pris trop de temps. Réessayez dans un instant.';
      case DioExceptionType.connectionError:
        return 'Impossible de joindre le serveur. Vérifiez votre connexion internet.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 401) return 'Vos identifiants sont incorrects ou votre session a expiré.';
        if (code == 403) return 'Vous n\'avez pas les droits pour effectuer cette action.';
        if (code == 404) return 'La ressource demandée est introuvable.';
        if (code == 422) {
          // Extraire les messages de validation si disponibles
          final data = e.response?.data;
          if (data is Map && data['message'] != null) {
            return data['message'].toString();
          }
          return 'Les données envoyées sont invalides. Vérifiez les champs du formulaire.';
        }
        if (code != null && code >= 500) {
          return 'Le serveur rencontre un problème temporaire. Réessayez plus tard.';
        }
        return 'Le serveur a retourné une erreur inattendue (code $code).';
      case DioExceptionType.cancel:
        return 'La requête a été annulée.';
      case DioExceptionType.unknown:
      default:
        return 'Une erreur de connexion est survenue. Vérifiez votre réseau et réessayez.';
    }
  }
}
