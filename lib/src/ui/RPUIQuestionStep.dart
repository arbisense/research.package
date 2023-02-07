part of research_package_ui;

/// The UI representation of the [RPQuestionStep]. This widget is the container, the concrete content depends on the input step's [RPAnswerFormat].
///
/// As soon as the participant has finished with the question the [RPStepResult] is being added to the [RPTaskResult]'s result list.
class RPUIQuestionStep extends StatefulWidget {
  final RPQuestionStep step;

  const RPUIQuestionStep(this.step, {super.key});

  @override
  RPUIQuestionStepState createState() => RPUIQuestionStepState();
}

class RPUIQuestionStepState extends State<RPUIQuestionStep> with CanSaveResult {
  // Dynamic because we don't know what value the RPChoice will have
  dynamic _currentQuestionBodyResult;
  late bool readyToProceed;
  late RPStepResult result;
  RPTaskProgress? recentTaskProgress;

  set currentQuestionBodyResult(dynamic currentQuestionBodyResult) {
    _currentQuestionBodyResult = currentQuestionBodyResult;
    createAndSendResult();
    if (_currentQuestionBodyResult != null) {
      blocQuestion.sendReadyToProceed(true);
    } else {
      blocQuestion.sendReadyToProceed(false);
    }
  }

  void skipQuestion() {
    FocusManager.instance.primaryFocus?.unfocus();
    blocTask.sendStatus(RPStepStatus.Finished);
    currentQuestionBodyResult = null;
  }

  @override
  void initState() {
    // Instantiating the result object here to start the time counter (startDate)
    super.initState();

    result = RPStepResult(
        identifier: widget.step.identifier,
        questionTitle: widget.step.title,
        answerFormat: widget.step.answerFormat);
    readyToProceed = false;
    blocQuestion.sendReadyToProceed(false);
    recentTaskProgress = blocTask.lastProgressValue;
  }

  // Returning the according step body widget based on the answerFormat of the step
  Widget stepBody(RPAnswerFormat answerFormat) {
    switch (answerFormat.runtimeType) {
      case RPIntegerAnswerFormat:
        return RPUIIntegerQuestionBody((answerFormat as RPIntegerAnswerFormat),
            (result) {
          currentQuestionBodyResult = result;
        });
      case RPDoubleAnswerFormat:
        return RPUIDoubleQuestionBody((answerFormat as RPDoubleAnswerFormat),
                (result) {
              currentQuestionBodyResult = result;
            });
      case RPChoiceAnswerFormat:
        return RPUIChoiceQuestionBody((answerFormat as RPChoiceAnswerFormat),
            (result) {
          currentQuestionBodyResult = result;
        });
      case RPSliderAnswerFormat:
        return RPUISliderQuestionBody((answerFormat as RPSliderAnswerFormat),
            (result) {
          currentQuestionBodyResult = result;
        });
      case RPImageChoiceAnswerFormat:
        return RPUIImageChoiceQuestionBody(
            (answerFormat as RPImageChoiceAnswerFormat), (result) {
          currentQuestionBodyResult = result;
        });
      case RPDateTimeAnswerFormat:
        return RPUIDateTimeQuestionBody(
            (answerFormat as RPDateTimeAnswerFormat), (result) {
          currentQuestionBodyResult = result;
        });
      case RPTextAnswerFormat:
        return RPUITextInputQuestionBody((answerFormat as RPTextAnswerFormat),
            (result) {
          currentQuestionBodyResult = result;
        });
      default:
        return Container();
    }
  }

  @override
  Widget build(BuildContext context) {
    RPLocalizations? locale = RPLocalizations.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          // Title
          Padding(
            padding:
                const EdgeInsets.only(bottom: 24, left: 8, right: 8, top: 0),
            child: Text(
              locale?.translate(widget.step.title) ?? widget.step.title,
              textAlign: TextAlign.left,
              style: Theme.of(context).textTheme.headline6,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: stepBody(widget.step.answerFormat),
          ),
          widget.step.optional
              ? TextButton(
                  onPressed: () => skipQuestion(),
                  child: Text(locale?.translate("Skip this question") ??
                      "Skip this question"),
                )
              : Container(),
        ],
      ),
    );
  }

  @override
  void createAndSendResult() {
    result.questionTitle = widget.step.title;
    result.setResult(_currentQuestionBodyResult);
    blocTask.sendStepResult(result);
  }
}

// Render the title above the questionBody
class Title extends StatelessWidget {
  final String title;
  const Title(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    if (title.contains('</')) {
      return HTML.toRichText(context, title);
    } else {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24, left: 8, right: 8, top: 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.headline6,
          textAlign: TextAlign.start,
        ),
      );
    }
  }
}
