import 'dart:async';
import 'dart:convert';

import 'package:carp_themes_package/carp_themes_package.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_package/research_package.dart';

/// Verifies that the permissions declared on a consent section are asked for
/// when leaving it, and only when the step opted in with `askPermission`.
///
/// [RPPermissionType.camera] is used throughout and the `permission_handler`
/// method channel is faked, so the real request path runs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The channel of the `permission_handler` plugin, faked below.
  const permissionChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );

  /// What reaches the channel when the camera is requested - the platform
  /// value of `Permission.camera`.
  const cameraRequest = [1];

  /// A document whose first section asks for the camera and whose second asks
  /// for nothing.
  RPConsentDocument documentWithCameraOnFirstSection() => RPConsentDocument(
    title: 'Consent',
    sections: [
      RPConsentSection(
        // A Custom section, so no image asset of the package is needed.
        type: RPConsentSectionType.Custom,
        title: 'Camera',
        summary: 'Why we need your camera',
        customIllustration: const SizedBox.shrink(),
        permissions: [RPPermissionType.camera],
      ),
      RPConsentSection(
        type: RPConsentSectionType.Custom,
        title: 'Your rights',
        summary: 'What you can do',
        customIllustration: const SizedBox.shrink(),
      ),
    ],
  );

  /// A three section document whose *middle* section asks for the camera.
  RPConsentDocument documentWithCameraOnMiddleSection() => RPConsentDocument(
    title: 'Consent',
    sections: [
      RPConsentSection(
        type: RPConsentSectionType.Custom,
        title: 'Welcome',
        summary: 'What this study is about',
        customIllustration: const SizedBox.shrink(),
      ),
      RPConsentSection(
        type: RPConsentSectionType.Custom,
        title: 'Camera',
        summary: 'Why we need your camera',
        customIllustration: const SizedBox.shrink(),
        permissions: [RPPermissionType.camera],
      ),
      RPConsentSection(
        type: RPConsentSectionType.Custom,
        title: 'Your rights',
        summary: 'What you can do',
        customIllustration: const SizedBox.shrink(),
      ),
    ],
  );

  Widget app(RPVisualConsentStep step) => MaterialApp(
    theme: carpTheme,
    home: RPUIVisualConsentStep(step: step),
  );

  /// Taps the forward button of the consent step and settles.
  Future<void> tapForward(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// The permissions passed to `requestPermissions`, one entry per call.
  late List<List<int>> requested;
  late List<RPResult> sentResults;
  late StreamSubscription<RPResult> subscription;

  /// The platform status the faked plugin answers with - granted is 1, denied
  /// is 0.
  late int answeredStatus;

  setUp(() {
    ResearchPackage.ensureInitialized();
    requested = [];
    sentResults = [];
    answeredStatus = 1;
    subscription = blocTask.stepResult.listen(sentResults.add);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
          if (call.method != 'requestPermissions') return null;
          final permissions = (call.arguments as List).cast<int>();
          requested.add(permissions);
          return {for (var p in permissions) p: answeredStatus};
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
    await subscription.cancel();
  });

  testWidgets(
    'askPermission asks for the permissions of the section on screen',
    (tester) async {
      await tester.pumpWidget(
        app(
          RPVisualConsentStep(
            identifier: 'visualStep',
            consentDocument: documentWithCameraOnFirstSection(),
            askPermission: true,
          ),
        ),
      );

      // Only asked for when the participant moves on from the section.
      expect(requested, isEmpty);

      await tapForward(tester, 'NEXT');
      expect(requested, [cameraRequest]);
    },
  );

  testWidgets('the outcome is added to the task result when the step finishes', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        RPVisualConsentStep(
          identifier: 'visualStep',
          consentDocument: documentWithCameraOnFirstSection(),
          askPermission: true,
        ),
      ),
    );

    await tapForward(tester, 'NEXT');
    // The result is only sent once, at the end of the step - not per section.
    expect(sentResults, isEmpty);

    await tapForward(tester, 'SEE SUMMARY');

    expect(sentResults, hasLength(1));
    final result = sentResults.single;
    expect(result, isA<RPPermissionResult>());
    // Keyed by the step identifier, as RPUITask files it.
    expect(result.identifier, 'visualStep');
    expect((result as RPPermissionResult).statuses, {
      RPPermissionType.camera: RPPermissionStatus.granted,
    });
  });

  testWidgets('an already granted permission is not asked for twice', (
    tester,
  ) async {
    final document = documentWithCameraOnFirstSection();
    // Both sections ask for the camera, so the second would prompt again if
    // granted permissions were not skipped.
    document.sections.last.permissions = [RPPermissionType.camera];

    await tester.pumpWidget(
      app(
        RPVisualConsentStep(
          identifier: 'visualStep',
          consentDocument: document,
          askPermission: true,
        ),
      ),
    );

    await tapForward(tester, 'NEXT');
    await tapForward(tester, 'SEE SUMMARY');

    expect(requested, [cameraRequest]);
  });

  testWidgets('without askPermission nothing is requested or recorded', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        RPVisualConsentStep(
          identifier: 'visualStep',
          consentDocument: documentWithCameraOnFirstSection(),
          // Not passing askPermission at all - it has to stay opt-out.
        ),
      ),
    );

    await tapForward(tester, 'NEXT');
    await tapForward(tester, 'SEE SUMMARY');

    expect(requested, isEmpty);
    expect(sentResults, isEmpty);
  });

  testWidgets('a refused permission is recorded as denied', (tester) async {
    answeredStatus = 0;

    await tester.pumpWidget(
      app(
        RPVisualConsentStep(
          identifier: 'visualStep',
          consentDocument: documentWithCameraOnFirstSection(),
          askPermission: true,
        ),
      ),
    );
    await tapForward(tester, 'NEXT');
    await tapForward(tester, 'SEE SUMMARY');

    expect(requested, [cameraRequest]);
    // Recorded, not blocking - the participant still reaches the end.
    expect((sentResults.single as RPPermissionResult).statuses, {
      RPPermissionType.camera: RPPermissionStatus.denied,
    });
  });

  /// A screen explaining an upcoming permission request may offer no way out
  /// but the alert it leads to (Apple HIG, Privacy). These tests pin the
  /// resulting button layout.
  group('a section explaining a permission offers no way out but the alert', () {
    testWidgets('it carries the forward button and nothing else', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          RPVisualConsentStep(
            identifier: 'visualStep',
            consentDocument: documentWithCameraOnMiddleSection(),
            askPermission: true,
          ),
        ),
      );

      // Onto the camera section - not the first, so it would show Back.
      await tapForward(tester, 'NEXT');
      expect(find.text('Camera'), findsOneWidget);

      expect(find.text('BACK'), findsNothing);
      expect(find.text('CANCEL'), findsNothing);
    });

    testWidgets('Back returns once the alert has been shown', (tester) async {
      await tester.pumpWidget(
        app(
          RPVisualConsentStep(
            identifier: 'visualStep',
            consentDocument: documentWithCameraOnMiddleSection(),
            askPermission: true,
          ),
        ),
      );

      // Onto the camera section, then past it - which is what shows the alert.
      await tapForward(tester, 'NEXT');
      await tapForward(tester, 'NEXT');
      expect(requested, [cameraRequest]);

      // No longer about to open an alert, so it behaves normally again.
      await tapForward(tester, 'BACK');
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('BACK'), findsOneWidget);
    });

    testWidgets('the consent step has no cancel button at all', (tester) async {
      await tester.pumpWidget(
        app(
          RPVisualConsentStep(
            identifier: 'visualStep',
            consentDocument: documentWithCameraOnMiddleSection(),
          ),
        ),
      );

      for (var section = 0; section < 3; section++) {
        expect(find.text('CANCEL'), findsNothing);
        if (section < 2) await tapForward(tester, 'NEXT');
      }
    });
  });

  group('navigating back through the consent sections', () {
    testWidgets('the first section has nothing to go back to', (tester) async {
      await tester.pumpWidget(
        app(
          RPVisualConsentStep(
            identifier: 'visualStep',
            consentDocument: documentWithCameraOnMiddleSection(),
          ),
        ),
      );

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('BACK'), findsNothing);
    });

    testWidgets('Back returns to the previous section', (tester) async {
      await tester.pumpWidget(
        app(
          RPVisualConsentStep(
            identifier: 'visualStep',
            // Without askPermission no section is a permission screen.
            consentDocument: documentWithCameraOnMiddleSection(),
          ),
        ),
      );

      await tapForward(tester, 'NEXT');
      expect(find.text('Camera'), findsOneWidget);

      await tapForward(tester, 'BACK');
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('BACK'), findsNothing);
    });

    testWidgets('leaving the last section restores the NEXT label', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          RPVisualConsentStep(
            identifier: 'visualStep',
            consentDocument: documentWithCameraOnMiddleSection(),
          ),
        ),
      );

      await tapForward(tester, 'NEXT');
      await tapForward(tester, 'NEXT');
      expect(find.text('SEE SUMMARY'), findsOneWidget);

      // Going back has to un-set "last page", or the forward button would
      // finish the step from the middle of the document.
      await tapForward(tester, 'BACK');
      expect(find.text('SEE SUMMARY'), findsNothing);
      expect(find.text('NEXT'), findsOneWidget);
    });
  });

  group('the close button of the task', () {
    RPConsentReviewStep reviewStep(RPConsentDocument document) =>
        RPConsentReviewStep(
          identifier: 'reviewStep',
          title: 'Review',
          consentDocument: document,
        );

    RPVisualConsentStep visualStep(RPConsentDocument document) =>
        RPVisualConsentStep(
          identifier: 'visualStep',
          consentDocument: document,
        );

    Future<void> pumpTask(WidgetTester tester, RPOrderedTask task) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: carpTheme,
          home: RPUITask(
            task: task,
            // The default is an asset, which no widget test resolves.
            carouselBarImage: Image.memory(transparentPixelPng),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'an informed consent flow has none - it is left with DISAGREE',
      (tester) async {
        final document = documentWithCameraOnMiddleSection();
        await pumpTask(
          tester,
          // The presence of a review step is what makes this a consent task.
          RPOrderedTask(
            identifier: 'consentTask',
            steps: [visualStep(document), reviewStep(document)],
          ),
        );

        expect(find.byIcon(Icons.highlight_off), findsNothing);
      },
    );

    testWidgets('any other task keeps it', (tester) async {
      final document = documentWithCameraOnMiddleSection();
      await pumpTask(
        tester,
        RPOrderedTask(identifier: 'plainTask', steps: [visualStep(document)]),
      );

      expect(find.byIcon(Icons.highlight_off), findsOneWidget);
    });
  });
}

/// A 1x1 transparent PNG, so a test can supply an image without an asset.
final Uint8List transparentPixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);
