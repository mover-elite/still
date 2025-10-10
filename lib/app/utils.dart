import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_app/app/models/contact_info.dart';
import 'package:flutter_app/resources/widgets/email_verification_bottom_sheet_widget.dart'
    show EmailVerificationBottomSheet;
import 'package:flutter_app/resources/widgets/phone_verification_bottom_sheet_widget.dart'
    show PhoneVerificationBottomSheet;
import 'package:nylo_framework/nylo_framework.dart';
import 'package:url_launcher/url_launcher.dart';

import '../resources/widgets/email_login_bottom_sheet_widget.dart';
import '../resources/widgets/phone_login_bottom_sheet_widget.dart';

class LoginBottomSheets {
  // Email Login Bottom Sheet
  static void showEmailBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const EmailLoginBottomSheet(),
    );
  }

  // Phone Login Bottom Sheet
  static void showPhoneBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const PhoneLoginBottomSheet(),
    );
  }

  // Email Verification Bottom Sheet
  static void showEmailVerificationBottomSheet(
      BuildContext context, String email) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => EmailVerificationBottomSheet(email: email),
    );
  }

  // Phone Verification Bottom Sheet
  static void showPhoneVerificationBottomSheet(
      BuildContext context, String phone) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => PhoneVerificationBottomSheet(phone: phone),
    );
  }
}

class ContactManager {
  static List<ContactInfo> getSampleContacts() {
    List<ContactInfo> contacts = [
      ContactInfo.create(
        name: "Eleanor",
        imagePath: "image7.png",
        tagIndex: "E",
      ),
      ContactInfo.create(
        name: "Layla B",
        imagePath: "image1.png",
        tagIndex: "L",
      ),
      ContactInfo.create(
        name: "Gadia",
        imagePath: "image4.png",
        tagIndex: "G",
      ),
      ContactInfo.create(
        name: "Arthur",
        imagePath: "image2.png",
        tagIndex: "A",
      ),
      ContactInfo.create(
        name: "Amanda",
        imagePath: "image3.png",
        tagIndex: "A",
      ),
      ContactInfo.create(
        name: "Al-Amin",
        imagePath: "image5.png",
        tagIndex: "A",
      ),
      ContactInfo.create(
        name: "Ahmad",
        imagePath: "image2.png",
        tagIndex: "A",
      ),
      ContactInfo.create(
        name: "Arafat",
        imagePath: "image10.png",
        tagIndex: "A",
      ),
      ContactInfo.create(
        name: "Aljandro",
        imagePath: "image11.png",
        tagIndex: "A",
      ),
      ContactInfo.create(
        name: "Alberto",
        imagePath: "image1.png",
        tagIndex: "A",
      ),
      ContactInfo.create(
        name: "Ben",
        imagePath: "image3.png",
        tagIndex: "B",
      ),
      ContactInfo.create(
        name: "Brian",
        imagePath: "image4.png",
        tagIndex: "B",
      ),
      ContactInfo.create(
        name: "Carlos",
        imagePath: "image5.png",
        tagIndex: "C",
      ),
      ContactInfo.create(
        name: "Chris",
        imagePath: "image7.png",
        tagIndex: "C",
      ),
      ContactInfo.create(
        name: "David",
        imagePath: "image8.png",
        tagIndex: "D",
      ),
      ContactInfo.create(
        name: "Daniel",
        imagePath: "image9.png",
        tagIndex: "D",
      ),
    ];

    // Sort contacts alphabetically
    contacts.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

    // Set section headers
    _setSectionHeaders(contacts);

    return contacts;
  }

  static void _setSectionHeaders(List<ContactInfo> contacts) {
    String currentTag = "";
    for (int i = 0; i < contacts.length; i++) {
      String tag = (contacts[i].name ?? '')[0].toUpperCase();
      if (tag != currentTag) {
        contacts[i].tagIndex = tag;
        contacts[i].isShowSuspension = true;
        currentTag = tag;
      } else {
        contacts[i].isShowSuspension = false;
      }
    }
  }

  // Save contacts to local storage
  static Future<void> saveContacts(List<ContactInfo> contacts) async {
    try {
      List contactsJson = contacts.map((contact) => contact.toJson()).toList();
      await NyStorage.save('contacts', contactsJson);
    } catch (e) {
      print('Error saving contacts: $e');
    }
  }

  // Load contacts from local storage
  static Future<List<ContactInfo>> loadContacts() async {
    try {
      List<dynamic>? contactsData = await NyStorage.read<List>('contacts');
      if (contactsData != null) {
        return contactsData.map((data) => ContactInfo.fromJson(data)).toList();
      }
    } catch (e) {
      print('Error loading contacts: $e');
    }
    return getSampleContacts(); // Return sample data if no saved data
  }
}

class TextUtils {

  static RegExp urlPattern = RegExp(
    r'(https?://[^\s]+)|(www\.[^\s]+)|(\b[a-zA-Z0-9][a-zA-Z0-9\-]*\.[a-zA-Z]{2,}(?:/[^\s]*)?)',
    caseSensitive: false,
  );

  static bool containsLink(String text) {
    return urlPattern.hasMatch(text);
    
  }
  
  static List<String> extractLinks(String text) {
    return urlPattern.allMatches(text).map((match) => match.group(0)!).toList();
  }

  /// Parse text and return a list of text spans with links highlighted
  static List<TextSpan> parseTextWithLinks(String text, {
    TextStyle? defaultStyle,
    TextStyle? linkStyle,
    Function(String)? onLinkTap,
  }) {
    

    List<TextSpan> spans = [];
    int lastIndex = 0;

    for (final match in urlPattern.allMatches(text)) {
      // Add text before the link
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: defaultStyle,
        ));
      }

      // Add the link
      String url = match.group(0)!;
      // Ensure URL has proper protocol
      String fullUrl = url;
      if (url.startsWith('www.')) {
        fullUrl = 'https://$url';
      } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
        fullUrl = 'https://$url';
      }
      
      spans.add(TextSpan(
        text: url,
        style: linkStyle ?? const TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => onLinkTap?.call(fullUrl),
      ));

      lastIndex = match.end;
    }

    // Add remaining text after the last link
    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: defaultStyle,
      ));
    }

    return spans.isEmpty ? [TextSpan(text: text, style: defaultStyle)] : spans;
  }

  /// Create a RichText widget with clickable links
  static Widget buildTextWithLinks(String text, {
    TextStyle? style,
    TextStyle? linkStyle,
    Function(String)? onLinkTap,
    TextAlign? textAlign,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    return RichText(
      text: TextSpan(
        children: parseTextWithLinks(
          text,
          defaultStyle: style,
          linkStyle: linkStyle,
          onLinkTap: onLinkTap ?? _launchURL,
        ),
      ),
      textAlign: textAlign ?? TextAlign.start,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }

  /// Launch URL in browser
  static Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }
}