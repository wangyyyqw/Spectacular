import 'cloud_http.dart';
import 'cloud_models.dart';
import 'providers/aliyun_provider.dart';
import 'providers/baidu_provider.dart';
import 'providers/lanzou_provider.dart';
import 'providers/pan123_provider.dart';
import 'providers/pikpak_provider.dart';
import 'providers/quark_provider.dart';
import 'providers/tianyi_provider.dart';

CloudProviderApi cloudProvider(CloudDrive drive, CloudHttp http) =>
    switch (drive) {
      CloudDrive.baidu => BaiduCloudProvider(http),
      CloudDrive.quark => QuarkCloudProvider(http),
      CloudDrive.aliyun => AliyunCloudProvider(http),
      CloudDrive.pan123 => Pan123CloudProvider(http),
      CloudDrive.tianyi => TianyiCloudProvider(http),
      CloudDrive.pikpak => PikPakCloudProvider(http),
      CloudDrive.lanzou => LanzouCloudProvider(http),
    };
