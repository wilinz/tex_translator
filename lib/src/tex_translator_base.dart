import 'dart:convert';
import 'dart:io';

import 'package:openai_dart_dio/openai_dart_dio.dart';
import 'package:path/path.dart';

Future<void> translateTeX({
  required String folderPath,
  required String outputDirPath,
  required String openaiApiKey,
  required String baseUrl,
  required bool forceTranslation,
  required int groupLength,
  required String model,
  required double temperature,
  required String targetLanguage,
}) async {
  final sourceDir = Directory(folderPath);
  if (!sourceDir.existsSync()) {
    print('Error: Folder "$folderPath" does not exist.');
    exit(1);
  }

  final outputDir = Directory(outputDirPath);
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }

  final openai = OpenAiClient(apiKey: openaiApiKey, baseUrl: baseUrl);

  await copyNonTexFiles(sourceDir, outputDir);

  final files =
      sourceDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.tex'))
          .toList();

  if (files.isEmpty) {
    print('No .tex files found in folder "$folderPath".');
    exit(0);
  }

  // 进度文件路径
  final progressFilePath = join(folderPath, 'translation_progress.json');
  final progressFile = File(progressFilePath);

  // 读取现有的进度文件（如果存在）
  Map<String, dynamic> progress = {};
  if (await progressFile.exists()) {
    final content = await progressFile.readAsString();
    progress = jsonDecode(content);
  } else {
    await progressFile.create(recursive: true);
  }

  // 如果强制从头开始翻译，清空进度文件
  if (forceTranslation) {
    print('Force translation from the beginning, clearing progress...');
    progress = {};
  }

  // 获取当前时间戳（用于确保每次翻译都会刷新）
  final currentTimestamp = DateTime.now().millisecondsSinceEpoch;

  for (final file in files) {
    print('Starting translation for file: ${file.path}');

    final originalContent = await file.readAsString();

    // 获取文件的当前进度（如果有）
    final fileName = file.uri.pathSegments.last;
    // final fileProgress = progress[fileName] ?? {'translatedChars': 0};

    // 计算剩余内容（原文减去已翻译内容）
    String remainingContent = originalContent; /*.substring(
      fileProgress['translatedChars'] as int,
    );*/

    // 分组逻辑，避免请求体积过大
    print('Group length: $groupLength');
    final maxGroupLength = groupLength;
    final lines = remainingContent.split('\n');
    final List<String> groups = [];
    StringBuffer currentBuffer = StringBuffer();
    int currentLength = 0;

    for (final line in lines) {
      final lineWithNewline = "$line\n";
      if (currentLength + lineWithNewline.length > maxGroupLength) {
        groups.add(currentBuffer.toString());
        currentBuffer = StringBuffer();
        currentLength = 0;
      }
      currentBuffer.write(lineWithNewline);
      currentLength += lineWithNewline.length;
    }
    if (currentLength > 0) {
      groups.add(currentBuffer.toString());
    }

    final List<String> translatedGroups = [];

    // 总翻译任务数
    final totalChunks = groups.length;

    // 显示文件的进度
    for (var i = 0; i < totalChunks; i++) {
      final text = groups[i];
      final chunkNumber = i + 1;

      stdout.write(
        '\rTranslating file: ${file.uri.pathSegments.last} [${chunkNumber}/$totalChunks]...',
      );

      final answer = await getTranslationAnswer(
        openai,
        model: model,
        temperature: temperature,
        content: text,
        targetLanguage: targetLanguage,
      );
      translatedGroups.add(answer);

      // 更新进度信息
      // fileProgress['translatedChars'] =
      //     (fileProgress['translatedChars'] as int) + answer.length;
      //
      // // 更新进度文件
      // progress[fileName] = fileProgress;

      // 每次翻译后保存进度
      // await progressFile.writeAsString(jsonEncode(progress));

      // 打印进度条
      double progressPercentage = chunkNumber / totalChunks;
      String progressBar =
          '[${'=' * (progressPercentage * 20).toInt()}>${' ' * (20 - (progressPercentage * 20).toInt())}]';
      stdout.write(
        ' $progressBar ${((progressPercentage) * 100).toStringAsFixed(2)}%',
      );

      // 延迟模拟翻译处理，避免过快
      await Future.delayed(Duration(milliseconds: 100));
    }

    var finalTranslatedContent = translatedGroups.join('\n');

    // 确保插入 \usepackage[UTF8]{ctex}
    // 确保在 \documentclass 后插入 \usepackage[UTF8]{ctex}
    if (!finalTranslatedContent.contains(r'\usepackage[UTF8]{ctex}')) {
      final lines = finalTranslatedContent.split('\n');
      final buffer = StringBuffer();
      bool inserted = false;
      for (var line in lines) {
        // 跳过注释行（以 % 开头的行）
        if (line.trim().startsWith('%')) {
          buffer.writeln(line);
          continue;
        }

        // 在 \documentclass 后插入 \usepackage[UTF8]{ctex}
        if (!inserted && line.trim().startsWith(r'\documentclass')) {
          buffer.writeln(line);
          buffer.writeln(r'\usepackage[UTF8]{ctex}'); // 插入在后面
          inserted = true;
          continue; // 跳过下面的 `writeln(line)`，因为已经处理过了
        }

        // 添加当前行
        buffer.writeln(line);
      }

      finalTranslatedContent = buffer.toString();
    }

    print("\n");
    saveTranslatedFile(outputDir, file, finalTranslatedContent, sourceDir);

    // 更新进度文件的时间戳，确保下次翻译时文件不被覆盖
    // progress[fileName]['timestamp'] = currentTimestamp;
    await progressFile.writeAsString(jsonEncode(progress));

    print('Progress file updated.\n');
  }
}

Future<void> saveTranslatedFile(
  Directory outputDir,
  File file,
  String finalTranslatedContent,
  Directory sourceDir,
) async {
  // 计算相对路径
  String relativePath = relative(file.path, from: sourceDir.path);

  // 获取输出文件的完整路径（保留原目录结构）
  final outputFilePath = join(outputDir.path, relativePath);

  // 获取输出文件的目录并创建它
  final outputFileDir = Directory(dirname(outputFilePath));
  if (!await outputFileDir.exists()) {
    await outputFileDir.create(recursive: true); // 创建目录结构
  }

  // 创建并写入翻译内容
  final outputFile = File(outputFilePath);
  await outputFile.writeAsString(finalTranslatedContent);

  print('File saved to: ${outputFile.path}');
}

Future<String> getTranslationAnswer(
  OpenAiClient openai, {
  required String model,
  required double temperature,
  required String content,
  required String targetLanguage,
}) async {
  final translatePrompt =
      "Please translate the following LaTeX content to $targetLanguage.";

  for (var i = 0; i < 5; i++) {
    try {
      final resp = await openai.chatCompletionApi.createChatCompletion(
        ChatCompletionRequest(
          model: model,
          temperature: temperature,
          messages: [
            ChatMessage(
              role: ChatMessageRole.user,
              content:
                  "$translatePrompt "
                  "Preserve all LaTeX syntax, commands, symbols, equations, citations, and formatting exactly as in the original. "
                  "Do not remove or alter any LaTeX environments such as \\section{}, \\begin{}...\\end{}, math symbols like \\( ... \\), \\[ ... \\], \$...\$, or references like \\cite{}. "
                  "Only translate the natural language text content. "
                  "Return only the translated LaTeX text as plain text (no markdown formatting):\n$content",
            ),
          ],
          responseFormat: ResponseFormat(
            type: ResponseFormatType.jsonSchema,
            jsonSchema: {
              "name": "translated_result",
              "description": "translated result",
              "schema": {
                "type": "object",
                "properties": {
                  "translated_result": {"type": "string"},
                },
                "required": ["translated_result"],
              },
            },
          ),
        ),
      );

      final json = jsonDecode(resp.choices.first.message.content!);
      return json['translated_result'] as String;
    } catch (e) {
      print('Translation attempt ${i + 1} failed: $e');
      await Future.delayed(Duration(seconds: 2));
    }
  }
  throw Exception('Translation failed after multiple attempts');
}

Future<void> copyNonTexFiles(Directory sourceDir, Directory outputDir) async {
  final nonTexFiles =
      sourceDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => !f.path.endsWith('.tex'))
          .toList();

  if (nonTexFiles.isNotEmpty) {
    print(
      'Found ${nonTexFiles.length} non-tex files. Copying them to the output folder...',
    );
    for (final file in nonTexFiles) {
      String relativePath = relative(file.path, from: sourceDir.path);
      final outputFilePath = join(outputDir.path, relativePath);

      // 获取输出文件的目录并创建它
      final outputFileDir = Directory(dirname(outputFilePath));
      if (!await outputFileDir.exists()) {
        await outputFileDir.create(recursive: true); // 创建目录结构
      }

      // 拷贝文件
      await file.copy(outputFilePath);
      print('File copied to: $outputFilePath');
    }
  } else {
    print('No non-tex files found to copy.');
  }
}
