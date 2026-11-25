import 'package:flutter/material.dart' hide Text;

import '../l10n.dart';
import '../util.dart';

/// Política de privacidad y de seguridad (es / en).
/// Son textos informativos generales; no sustituyen asesoría legal.
class LegalScreen extends StatelessWidget {
  const LegalScreen.privacy({super.key}) : security = false;
  const LegalScreen.security({super.key}) : security = true;
  final bool security;

  static const _privEs = <List<String>>[
    ['1. Qué datos guardamos', 'Tu correo, nombre de usuario, foto, biografía y juegos favoritos; lo que publicas (fotos, videos, textos, comentarios, reacciones, mensajes); y, si tú lo decides, tu cumpleaños (solo se muestra día y mes). No pedimos tu teléfono ni tu dirección.'],
    ['2. Para qué los usamos', 'Para que la app funcione: crear tu cuenta, mostrar tu contenido, enviarte avisos de mensajes o comentarios y mantener la comunidad segura. No vendemos tus datos ni los usamos para publicidad.'],
    ['3. Quién puede ver qué', 'Tus publicaciones, perfil y comentarios los ven otros usuarios de la app. Tu correo y tu fecha de nacimiento completa nunca se muestran a otros. Los mensajes solo los ven los participantes del chat.'],
    ['4. Servicios que usamos', 'Guardamos los datos en Supabase y las fotos y videos en Cloudinary. Estos proveedores procesan la información solo para prestar el servicio.'],
    ['5. Tus derechos', 'Puedes editar o borrar tus publicaciones, tu cumpleaños y tu perfil cuando quieras. Si quieres que eliminemos tu cuenta y tus datos, escríbenos desde Contacto en la app.'],
    ['6. Menores', 'GamersLore es solo para mayores de 18 años. Si detectamos una cuenta de un menor, la eliminamos.'],
    ['7. Cambios', 'Podemos actualizar esta política. Si sigues usando la app después de un cambio, se entiende que lo aceptas.'],
  ];
  static const _privEn = <List<String>>[
    ['1. What data we keep', 'Your email, username, photo, bio and favorite games; what you post (photos, videos, text, comments, reactions, messages); and, only if you choose, your birthday (only day and month are shown). We do not ask for your phone number or address.'],
    ['2. What we use it for', 'To make the app work: create your account, show your content, send you notices about messages or comments and keep the community safe. We do not sell your data or use it for advertising.'],
    ['3. Who can see what', 'Your posts, profile and comments are visible to other users of the app. Your email and full date of birth are never shown to others. Messages are visible only to the people in the chat.'],
    ['4. Services we use', 'Data is stored with Supabase and photos and videos with Cloudinary. These providers process information only to provide the service.'],
    ['5. Your rights', 'You can edit or delete your posts, birthday and profile at any time. To have your account and data deleted, write to us from Contact in the app.'],
    ['6. Minors', 'GamersLore is only for people aged 18 or over. If we find an account belonging to a minor, we delete it.'],
    ['7. Changes', 'We may update this policy. If you keep using the app after a change, you accept it.'],
  ];
  static const _secEs = <List<String>>[
    ['1. Tu contraseña', 'Se guarda cifrada; nadie, ni nosotros, puede verla. Usa una contraseña larga y única, y no la compartas.'],
    ['2. Conexión segura', 'Toda la comunicación entre la app y los servidores va cifrada (HTTPS).'],
    ['3. Protección de los datos', 'Cada tabla de la base de datos tiene reglas de acceso: solo puedes cambiar lo que es tuyo. Hay límites para frenar el spam y los intentos repetidos de entrar.'],
    ['4. Moderación', 'Puedes denunciar y bloquear usuarios. El administrador revisa las denuncias y puede quitar contenido o suspender cuentas.'],
    ['5. Cuenta verificada', 'La insignia azul solo se da tras revisar la solicitud. Desconfía de quien te pida dinero o contraseñas.'],
    ['6. Cómo reportar un problema de seguridad', 'Si encuentras un fallo, escríbenos desde Contacto en la app con los detalles. Te agradecemos que no lo publiques antes de que lo arreglemos.'],
    ['7. Consejos', 'No abras enlaces sospechosos, no compartas códigos y cierra sesión en teléfonos ajenos.'],
  ];
  static const _secEn = <List<String>>[
    ['1. Your password', 'It is stored encrypted; nobody, not even us, can read it. Use a long, unique password and do not share it.'],
    ['2. Secure connection', 'All communication between the app and the servers is encrypted (HTTPS).'],
    ['3. Data protection', 'Every database table has access rules: you can only change what is yours. There are limits to slow down spam and repeated sign-in attempts.'],
    ['4. Moderation', 'You can report and block users. The administrator reviews reports and may remove content or suspend accounts.'],
    ['5. Verified account', 'The blue badge is only given after a request is reviewed. Be wary of anyone asking for money or passwords.'],
    ['6. Reporting a security problem', 'If you find a flaw, write to us from Contact in the app with the details. Please do not publish it before we fix it.'],
    ['7. Tips', 'Do not open suspicious links, do not share codes and sign out on other people’s phones.'],
  ];

  @override
  Widget build(BuildContext context) {
    final es = L.base == 'es';
    final data = security ? (es ? _secEs : _secEn) : (es ? _privEs : _privEn);
    final title = security ? 'Política de seguridad' : 'Política de privacidad';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final s in data) ...[
            Text(s[0], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(s[1], style: const TextStyle(height: 1.4)),
            const SizedBox(height: 18),
          ],
          Center(
            child: TextButton(
              onPressed: () => showContactDialog(context),
              child: const Text('Contacto'),
            ),
          ),
        ],
      ),
    );
  }
}
