import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {

    return MaterialApp(

      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),

      home: const IoTPage(),
    );
  }
}

class IoTPage extends StatefulWidget {
  const IoTPage({super.key});

  @override
  State<IoTPage> createState() => _IoTPageState();
}

class _IoTPageState extends State<IoTPage> {

  // ================= SENSOR =================
  double suhu = 0;
  double jarak = 0;

  // ================= STATUS =================
  bool isLoading = true;
  bool isConnected = false;
  bool isRequestRunning = false;

  // ================= SERVO =================
  String servoStatus = "CLOSE";

  // ================= TIMER =================
  Timer? timer;

  // ================= MQTT =================
  late MqttServerClient client;

  // ================= ANTARES =================
  final String accessKey =
      " ";

  final String projectName =
      "Testing_IOT";

  final String deviceName =
      "PA_IOT";

  // ================= URL =================
  late final String url;

  // ================= INIT =================
  @override
  void initState() {

    super.initState();

    url =
    "https://platform.antares.id:8443"
        "/~/antares-cse/antares-id/"
        "$projectName/$deviceName/la";

    connectMQTT();

    getData();

    // Realtime refresh
    timer = Timer.periodic(

      const Duration(seconds: 3),

          (_) {

        getData();
      },
    );
  }

  // ================= MQTT CONNECT =================
  Future<void> connectMQTT() async {

    client = MqttServerClient(

      'broker.emqx.io',

      'flutter_client_${DateTime.now().millisecondsSinceEpoch}',
    );

    client.port = 1883;

    client.keepAlivePeriod = 20;

    client.autoReconnect = true;

    client.logging(on: false);

    client.onConnected = () {

      print("MQTT Connected");

      // Subscribe status servo
      client.subscribe(
        "garage/servo/status",
        MqttQos.atMostOnce,
      );

      // Listen data
      client.updates!.listen((events) {

        final recMess =
        events[0].payload
        as MqttPublishMessage;

        final message =
        MqttPublishPayload
            .bytesToStringAsString(
          recMess.payload.message,
        );

        final topic =
            events[0].topic;

        print("TOPIC : $topic");
        print("MESSAGE : $message");

        if (mounted) {

          setState(() {

            if (topic ==
                "garage/servo/status") {

              servoStatus = message;
            }
          });
        }
      });
    };

    client.onDisconnected = () {

      print("MQTT Disconnected");
    };

    try {

      await client.connect();

    } catch (e) {

      print("MQTT ERROR : $e");

      client.disconnect();
    }
  }

  // ================= CONTROL SERVO =================
  void controlServo(String command) {

    // cek koneksi MQTT
    if (client.connectionStatus?.state !=
        MqttConnectionState.connected) {

      print("MQTT Not Connected");
      return;
    }

    try {

      final builder =
      MqttClientPayloadBuilder();

      builder.addString(command);

      client.publishMessage(

        "garage/servo",

        MqttQos.atMostOnce,

        builder.payload!,
      );

      setState(() {

        servoStatus = command;
      });

      print("Servo Command : $command");

    } catch (e) {

      print("SERVO ERROR : $e");
    }
  }

  // ================= GET DATA =================
  Future<void> getData() async {

    if (isRequestRunning) return;

    isRequestRunning = true;

    try {

      final response = await http.get(

        Uri.parse(url),

        headers: {

          "X-M2M-Origin":
          accessKey,

          "Content-Type":
          "application/json;ty=4",

          "Accept":
          "application/json",
        },

      ).timeout(
        const Duration(seconds: 15),
      );

      print(
        "STATUS CODE : ${response.statusCode}",
      );

      // ================= SUCCESS =================
      if (response.statusCode == 200) {

        final data =
        jsonDecode(response.body);

        final con =
        data["m2m:cin"]["con"];

        Map<String, dynamic> sensor;

        // Parse JSON
        if (con is String) {

          sensor = jsonDecode(con);

        } else {

          sensor =
          Map<String, dynamic>.from(con);
        }

        final newSuhu =
            double.tryParse(
              sensor["suhu"].toString(),
            ) ??
                0;

        final newJarak =
            double.tryParse(
              sensor["jarak"].toString(),
            ) ??
                0;

        if (mounted) {

          setState(() {

            suhu = newSuhu;
            jarak = newJarak;

            isConnected = true;
            isLoading = false;
          });
        }

      } else {

        print(
          "ERROR STATUS : ${response.statusCode}",
        );

        if (mounted) {

          setState(() {

            isConnected = false;
            isLoading = false;
          });
        }
      }

    }

    // ================= TIMEOUT =================
    on TimeoutException {

      print("TIMEOUT");

      if (mounted) {

        setState(() {

          isConnected = false;
          isLoading = false;
        });
      }
    }

    // ================= ERROR =================
    catch (e) {

      print("ERROR : $e");

      if (mounted) {

        setState(() {

          isConnected = false;
          isLoading = false;
        });
      }
    }

    finally {

      isRequestRunning = false;
    }
  }

  // ================= DISPOSE =================
  @override
  void dispose() {

    timer?.cancel();

    client.disconnect();

    super.dispose();
  }

  // ================= SENSOR CARD =================
  Widget sensorCard({

    required String title,

    required String value,

    required IconData icon,
  }) {

    return Card(

      elevation: 6,

      shape: RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(20),
      ),

      child: Padding(

        padding:
        const EdgeInsets.all(25),

        child: Column(

          children: [

            Icon(
              icon,
              size: 55,
              color: Colors.blue,
            ),

            const SizedBox(height: 15),

            Text(

              title,

              style: const TextStyle(

                fontSize: 24,

                fontWeight:
                FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            Text(

              value,

              style: const TextStyle(

                fontSize: 34,

                fontWeight:
                FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(

        title: const Text(
          "Smart Garage IoT",
        ),

        centerTitle: true,
      ),

      body: isLoading

          ? const Center(
        child:
        CircularProgressIndicator(),
        )

          : RefreshIndicator(

        onRefresh: getData,

        child: ListView(

          physics:
          const AlwaysScrollableScrollPhysics(),

          padding:
          const EdgeInsets.all(20),

          children: [

            // ================= STATUS =================
            Container(

              padding:
              const EdgeInsets.all(15),

              decoration: BoxDecoration(

                color: isConnected
                    ? Colors.green
                    : Colors.red,

                borderRadius:
                BorderRadius.circular(
                  15,
                ),
              ),

              child: Row(

                mainAxisAlignment:
                MainAxisAlignment.center,

                children: [

                  Icon(

                    isConnected
                        ? Icons.wifi
                        : Icons.wifi_off,

                    color: Colors.white,
                  ),

                  const SizedBox(width: 10),

                  Text(

                    isConnected
                        ? "Connected"
                        : "Disconnected",

                    style:
                    const TextStyle(

                      color: Colors.white,

                      fontSize: 18,

                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),

            // ================= SUHU =================
            sensorCard(

              title: "Suhu",

              value:
              "${suhu.toStringAsFixed(1)} °C",

              icon: Icons.thermostat,
            ),

            const SizedBox(height: 20),

            // ================= JARAK =================
            sensorCard(

              title: "Jarak",

              value:
              "${jarak.toStringAsFixed(1)} cm",

              icon:
              Icons.social_distance,
            ),

            const SizedBox(height: 20),

            // ================= SERVO =================


            const SizedBox(height: 20),

            // ================= REFRESH =================
            ElevatedButton.icon(

              onPressed: getData,

              icon: const Icon(
                Icons.refresh,
              ),

              label: const Text(
                "Refresh Data",
              ),

              style:
              ElevatedButton.styleFrom(

                padding:
                const EdgeInsets.all(15),

                shape:
                RoundedRectangleBorder(

                  borderRadius:
                  BorderRadius.circular(
                    15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
