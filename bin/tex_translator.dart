import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:tex_translator/tex_translator.dart';

Future<void> main(List<String> arguments) async {
  final parser =
      ArgParser()
        ..addOption(
          'source',
          abbr: 's',
          help: 'Path to the folder containing .tex files.',
          mandatory: true,
        )
        ..addOption(
          'apikey',
          abbr: 'k',
          help: 'OpenAI API key.',
          mandatory: true,
        )
        ..addOption(
          'baseurl',
          abbr: 'b',
          help: 'OpenAI API base URL.',
          defaultsTo: 'https://api.openai.com',
        )
        ..addOption(
          'target',
          abbr: 't',
          help: 'Target language, example: zh-CN, ja_JP, etc.',
          defaultsTo: 'zh',
        )
        ..addOption(
          'output',
          abbr: 'o',
          help:
              'Output directory for translated files. Defaults to <folder>_translated.',
        )
        ..addOption("model", abbr: "m", defaultsTo: "gpt-4o")
        ..addOption("temperature", aliases: ["temp"])
        ..addOption("group-length", aliases: ["gl"])
        ..addFlag(
          'force',
          abbr: 'f',
          help: 'Force translation from the beginning (ignore progress).',
          negatable: false,
        )
        ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  ArgResults argResults;
  try {
    argResults = parser.parse(arguments);
  } catch (e) {
    print('Error: $e');
    print(parser.usage);
    exit(1);
  }

  if (argResults['help'] as bool) {
    print('Usage:');
    print(parser.usage);
    exit(0);
  }

  final folderPath = argResults['source'] as String;
  final openaiApiKey = argResults['apikey'] as String;
  final baseUrl = argResults['baseurl'] as String;
  final targetLanguage = (argResults['target'] as String).toLowerCase();
  final outputDirPath =
      argResults['output'] as String? ?? '${folderPath}_translated';
  final forceTranslation = argResults['force'] as bool;
  final model = argResults['model'] as String;
  final temperature =
      double.tryParse(argResults['temperature'] as String? ?? "") ?? 0;
  final groupLength =
      int.tryParse(argResults['group-length'] as String? ?? "") ?? 5000;

  await translateTeX(
    folderPath: folderPath,
    outputDirPath: outputDirPath,
    openaiApiKey: openaiApiKey,
    baseUrl: baseUrl,
    forceTranslation: forceTranslation,
    groupLength: groupLength,
    model: model,
    temperature: temperature,
    targetLanguage: targetLanguage,
  );
}
