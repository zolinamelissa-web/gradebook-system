import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PlatformIcons {
  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static IconData adaptive({
    required IconData cupertino,
    required IconData material,
  }) {
    return cupertino;
  }

  static IconData get dashboard => adaptive(
    cupertino: CupertinoIcons.square_grid_2x2,
    material: Icons.dashboard,
  );

  static IconData get person =>
      adaptive(cupertino: CupertinoIcons.person, material: Icons.person);

  static IconData get personOutline => adaptive(
    cupertino: CupertinoIcons.person,
    material: Icons.person_outline,
  );

  static IconData get idNumber => adaptive(
    cupertino: CupertinoIcons.number,
    material: Icons.confirmation_number,
  );

  static IconData get lock =>
      adaptive(cupertino: CupertinoIcons.lock, material: Icons.lock_outline);

  static IconData get lockReset =>
      adaptive(cupertino: CupertinoIcons.lock, material: Icons.lock_reset);

  static IconData get verified => adaptive(
    cupertino: CupertinoIcons.check_mark_circled,
    material: Icons.verified,
  );

  static IconData get key =>
      adaptive(cupertino: CupertinoIcons.lock, material: Icons.vpn_key);

  static IconData get eye =>
      adaptive(cupertino: CupertinoIcons.eye, material: Icons.visibility);

  static IconData get eyeSlash => adaptive(
    cupertino: CupertinoIcons.eye_slash,
    material: Icons.visibility_off,
  );

  static IconData get students =>
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
      ? CupertinoIcons.person_2
      : adaptive(
          cupertino: CupertinoIcons.person_2,
          material: Icons.people_alt,
        );

  static IconData get classes =>
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
      ? CupertinoIcons.book
      : adaptive(cupertino: CupertinoIcons.book, material: Icons.class_);

  static IconData get analytics =>
      adaptive(cupertino: CupertinoIcons.chart_bar, material: Icons.bar_chart);

  static IconData get settings =>
      adaptive(cupertino: CupertinoIcons.gear, material: Icons.settings);

  static IconData get school => adaptive(
    cupertino: CupertinoIcons.building_2_fill,
    material: Icons.school,
  );

  static IconData get notifications {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return CupertinoIcons.bell;
    }
    return adaptive(
      cupertino: CupertinoIcons.bell,
      material: Icons.notifications,
    );
  }

  static IconData get notificationsActive {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return CupertinoIcons.bell_fill;
    }
    return adaptive(
      cupertino: CupertinoIcons.bell_fill,
      material: Icons.notifications_active,
    );
  }

  static IconData get close {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return CupertinoIcons.xmark;
    }
    return adaptive(cupertino: CupertinoIcons.xmark, material: Icons.close);
  }

  static IconData get chevronRight {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return CupertinoIcons.right_chevron;
    }
    return adaptive(
      cupertino: CupertinoIcons.right_chevron,
      material: Icons.chevron_right,
    );
  }

  static IconData get fullscreen => adaptive(
    cupertino: CupertinoIcons.arrow_up_left_arrow_down_right,
    material: Icons.fullscreen,
  );

  static IconData get logout => adaptive(
    cupertino: CupertinoIcons.square_arrow_right,
    material: Icons.logout,
  );

  static IconData get error => adaptive(
    cupertino: CupertinoIcons.exclamationmark_triangle,
    material: Icons.error_outline,
  );

  static IconData get signIn => adaptive(
    cupertino: CupertinoIcons.arrow_right_to_line,
    material: Icons.login,
  );

  static IconData get signUp => adaptive(
    cupertino: CupertinoIcons.person_badge_plus,
    material: Icons.person_add,
  );

  static IconData get people =>
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
      ? CupertinoIcons.person_3
      : adaptive(
          cupertino: CupertinoIcons.person_3,
          material: Icons.people_alt,
        );

  static IconData get personAdd => adaptive(
    cupertino: CupertinoIcons.person_badge_plus,
    material: Icons.person_add,
  );

  static IconData get warning => adaptive(
    cupertino: CupertinoIcons.exclamationmark_triangle_fill,
    material: (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        ? CupertinoIcons.exclamationmark_triangle_fill
        : Icons.warning_amber,
  );

  static IconData get construction =>
      adaptive(cupertino: CupertinoIcons.wrench, material: Icons.construction);

  static IconData get refresh =>
      adaptive(cupertino: CupertinoIcons.refresh, material: Icons.refresh);

  static IconData get search =>
      adaptive(cupertino: CupertinoIcons.search, material: Icons.search);

  static IconData get camera =>
      adaptive(cupertino: CupertinoIcons.camera, material: Icons.photo_camera);

  static IconData get photoLibrary =>
      adaptive(cupertino: CupertinoIcons.photo, material: Icons.photo_library);

  static IconData get back =>
      adaptive(cupertino: CupertinoIcons.back, material: Icons.chevron_left);

  static IconData get calendar => adaptive(
    cupertino: CupertinoIcons.calendar,
    material: Icons.calendar_today,
  );

  static IconData get calendarToday => adaptive(
    cupertino: CupertinoIcons.calendar,
    material: Icons.calendar_today,
  );

  static IconData get cloudDownload => adaptive(
    cupertino: CupertinoIcons.cloud_download,
    material: Icons.cloud_download,
  );

  static IconData get forward => adaptive(
    cupertino: CupertinoIcons.right_chevron,
    material: Icons.chevron_right,
  );

  static IconData get gender =>
      adaptive(cupertino: CupertinoIcons.person_2, material: Icons.wc);

  static IconData get badge => adaptive(
    cupertino: CupertinoIcons.person_crop_circle,
    material: Icons.badge,
  );

  static IconData get email =>
      adaptive(cupertino: CupertinoIcons.mail, material: Icons.email);

  static IconData get phone =>
      adaptive(cupertino: CupertinoIcons.phone, material: Icons.phone);

  static IconData get copy =>
      adaptive(cupertino: CupertinoIcons.doc_on_doc, material: Icons.copy);

  static IconData get location =>
      adaptive(cupertino: CupertinoIcons.location, material: Icons.location_on);

  static IconData get add =>
      adaptive(cupertino: CupertinoIcons.add, material: Icons.add);

  static IconData get book =>
      adaptive(cupertino: CupertinoIcons.book, material: Icons.menu_book);

  static IconData get group =>
      adaptive(cupertino: CupertinoIcons.group, material: Icons.group);

  static IconData get accountCircle => adaptive(
    cupertino: CupertinoIcons.person_crop_circle,
    material: Icons.account_circle,
  );

  static IconData get calculate =>
      adaptive(cupertino: CupertinoIcons.add, material: Icons.calculate);

  static IconData get event =>
      adaptive(cupertino: CupertinoIcons.calendar_today, material: Icons.event);

  static IconData get schedule =>
      adaptive(cupertino: CupertinoIcons.time, material: Icons.schedule);

  static IconData get room =>
      adaptive(cupertino: CupertinoIcons.location, material: Icons.room);

  static IconData get dropdown => adaptive(
    cupertino: CupertinoIcons.chevron_down,
    material: Icons.keyboard_arrow_down,
  );

  static IconData get grade =>
      adaptive(cupertino: CupertinoIcons.star, material: Icons.grade);

  static IconData get checkCircle => adaptive(
    cupertino: CupertinoIcons.check_mark_circled,
    material: Icons.check_circle,
  );

  static IconData get cloudSync => adaptive(
    cupertino: CupertinoIcons.cloud_upload,
    material: Icons.cloud_sync,
  );

  static IconData get cloudUpload => adaptive(
    cupertino: CupertinoIcons.cloud_upload,
    material: Icons.cloud_upload,
  );

  static IconData get upload =>
      adaptive(cupertino: CupertinoIcons.cloud_upload, material: Icons.upload);

  static IconData get download => adaptive(
    cupertino: CupertinoIcons.cloud_download,
    material: Icons.download,
  );

  static IconData get tableChart => adaptive(
    cupertino: CupertinoIcons.table_badge_more,
    material: Icons.table_chart,
  );

  static IconData get tune => adaptive(
    cupertino: CupertinoIcons.slider_horizontal_3,
    material: Icons.tune,
  );

  static IconData get groupAdd => adaptive(
    cupertino: CupertinoIcons.person_crop_circle_badge_plus,
    material: Icons.group_add,
  );

  static IconData get eventAvailable => adaptive(
    cupertino: CupertinoIcons.calendar_today,
    material: Icons.event_available,
  );

  static IconData get palette =>
      adaptive(cupertino: CupertinoIcons.paintbrush, material: Icons.palette);

  static IconData get delete => adaptive(
    cupertino: CupertinoIcons.delete,
    material: Icons.delete_outline,
  );

  static IconData get deleteSweep =>
      adaptive(cupertino: CupertinoIcons.delete, material: Icons.delete_sweep);

  static IconData get backup =>
      adaptive(cupertino: CupertinoIcons.archivebox, material: Icons.backup);

  static IconData get edit =>
      adaptive(cupertino: CupertinoIcons.pencil, material: Icons.edit);

  static IconData get archive =>
      adaptive(cupertino: CupertinoIcons.archivebox, material: Icons.archive);

  static IconData get unarchive =>
      adaptive(cupertino: CupertinoIcons.tray, material: Icons.unarchive);

  static IconData get calendarMonth => adaptive(
    cupertino: CupertinoIcons.calendar,
    material: Icons.calendar_month,
  );

  static IconData get factCheck => adaptive(
    cupertino: CupertinoIcons.checkmark_square,
    material: Icons.fact_check,
  );

  static IconData get quiz =>
      adaptive(cupertino: CupertinoIcons.question_circle, material: Icons.quiz);

  static IconData get assignment =>
      adaptive(cupertino: CupertinoIcons.doc_text, material: Icons.assignment);

  static IconData get score =>
      adaptive(cupertino: CupertinoIcons.chart_bar, material: Icons.score);

  static IconData get folderSpecial => adaptive(
    cupertino: CupertinoIcons.folder,
    material: Icons.folder_special,
  );

  static IconData get recordVoiceOver => adaptive(
    cupertino: CupertinoIcons.mic,
    material: Icons.record_voice_over,
  );

  static IconData get homeWork =>
      adaptive(cupertino: CupertinoIcons.house, material: Icons.home_work);

  static IconData get taskAlt => adaptive(
    cupertino: CupertinoIcons.checkmark_alt_circle,
    material: Icons.task_alt,
  );

  static IconData get rocketLaunch =>
      adaptive(cupertino: CupertinoIcons.rocket, material: Icons.rocket_launch);

  static IconData get category => adaptive(
    cupertino: CupertinoIcons.square_grid_2x2,
    material: Icons.category,
  );

  static IconData get class_ =>
      adaptive(cupertino: CupertinoIcons.square_list, material: Icons.class_);

  static IconData get eventNote =>
      adaptive(cupertino: CupertinoIcons.doc_text, material: Icons.event_note);

  static IconData get peopleOutline => adaptive(
    cupertino: CupertinoIcons.person_2,
    material: Icons.people_outline,
  );

  static IconData get pictureAsPdf => adaptive(
    cupertino: CupertinoIcons.doc_text,
    material: Icons.picture_as_pdf,
  );

  static IconData get chevronLeft => adaptive(
    cupertino: CupertinoIcons.left_chevron,
    material: Icons.chevron_left,
  );

  static IconData get inbox =>
      adaptive(cupertino: CupertinoIcons.tray, material: Icons.inbox);

  static IconData get howToReg => adaptive(
    cupertino: CupertinoIcons.checkmark_seal,
    material: Icons.how_to_reg,
  );

  static IconData get percent =>
      adaptive(cupertino: CupertinoIcons.percent, material: Icons.percent);

  static IconData get showChart =>
      adaptive(cupertino: CupertinoIcons.chart_bar, material: Icons.show_chart);

  static IconData get insights =>
      adaptive(cupertino: CupertinoIcons.lightbulb, material: Icons.insights);

  static IconData get article =>
      adaptive(cupertino: CupertinoIcons.doc_text, material: Icons.article);

  static IconData get libraryBooks =>
      adaptive(cupertino: CupertinoIcons.book, material: Icons.library_books);

  static IconData get moreVert =>
      adaptive(cupertino: CupertinoIcons.ellipsis, material: Icons.more_vert);

  static IconData get editNote => adaptive(
    cupertino: CupertinoIcons.pencil_outline,
    material: Icons.edit_note,
  );

  static IconData get driveFileRename => adaptive(
    cupertino: CupertinoIcons.text_cursor,
    material: Icons.drive_file_rename_outline,
  );

  static IconData get swapHoriz => adaptive(
    cupertino: CupertinoIcons.arrow_left_right,
    material: Icons.swap_horiz,
  );

  static IconData get dateRange => adaptive(
    cupertino: CupertinoIcons.calendar_today,
    material: Icons.date_range,
  );

  static IconData get flag =>
      adaptive(cupertino: CupertinoIcons.flag, material: Icons.flag);

  static IconData get support => adaptive(
    cupertino: CupertinoIcons.chat_bubble_2,
    material: Icons.support,
  );

  static IconData get viewList => adaptive(
    cupertino: CupertinoIcons.list_bullet,
    material: Icons.view_list,
  );

  static IconData get groupOff =>
      adaptive(cupertino: CupertinoIcons.person_3, material: Icons.group_off);

  static IconData get workspacePremium => adaptive(
    cupertino: CupertinoIcons.star_circle,
    material: Icons.workspace_premium,
  );

  static IconData get dragHandle => adaptive(
    cupertino: CupertinoIcons.line_horizontal_3,
    material: Icons.drag_indicator,
  );

  static IconData get iosShare =>
      adaptive(cupertino: CupertinoIcons.share, material: Icons.ios_share);

  static IconData get gridOn => adaptive(
    cupertino: CupertinoIcons.square_grid_3x2,
    material: Icons.grid_on,
  );

  static IconData get checkCircleOutline => adaptive(
    cupertino: CupertinoIcons.circle,
    material: Icons.check_circle_outline,
  );

  static IconData get info =>
      adaptive(cupertino: CupertinoIcons.info_circle, material: Icons.info);

  static IconData get cancel =>
      adaptive(cupertino: CupertinoIcons.xmark_circle, material: Icons.cancel);

  static IconData get watchLater =>
      adaptive(cupertino: CupertinoIcons.clock, material: Icons.watch_later);

  static IconData get timeline =>
      adaptive(cupertino: CupertinoIcons.chart_bar, material: Icons.timeline);

  static IconData get eventBusy => adaptive(
    cupertino: CupertinoIcons.calendar_badge_minus,
    material: Icons.event_busy,
  );

  static IconData get errorOutline => adaptive(
    cupertino: CupertinoIcons.exclamationmark_triangle,
    material: Icons.error_outline,
  );

  static IconData get uploadFile => adaptive(
    cupertino: CupertinoIcons.cloud_upload,
    material: Icons.upload_file,
  );

  static IconData get autoAwesome => adaptive(
    cupertino: CupertinoIcons.sparkles,
    material: Icons.auto_awesome,
  );

  static IconData get title =>
      adaptive(cupertino: CupertinoIcons.textformat, material: Icons.title);

  static IconData get description =>
      adaptive(cupertino: CupertinoIcons.doc_text, material: Icons.description);

  static IconData get save =>
      adaptive(cupertino: CupertinoIcons.floppy_disk, material: Icons.save);

  static IconData get clear =>
      adaptive(cupertino: CupertinoIcons.clear, material: Icons.clear);

  static IconData get removeCircleOutline => adaptive(
    cupertino: CupertinoIcons.minus_circle,
    material: Icons.remove_circle_outline,
  );

  static IconData get addCircleOutline => adaptive(
    cupertino: CupertinoIcons.add_circled,
    material: Icons.add_circle_outline,
  );

  static IconData get confirmationNumber => adaptive(
    cupertino: CupertinoIcons.number,
    material: Icons.confirmation_number,
  );

  static IconData get check => adaptive(
    cupertino: CupertinoIcons.check_mark,
    material: Icons.check_circle,
  );

  static IconData get circle =>
      adaptive(cupertino: CupertinoIcons.circle_fill, material: Icons.circle);

  static IconData get backspace => adaptive(
    cupertino: CupertinoIcons.delete_left,
    material: Icons.backspace,
  );
}
