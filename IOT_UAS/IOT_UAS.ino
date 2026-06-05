#include <WiFi.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <PubSubClient.h>
#include <AntaresESPHTTP.h>

// ================= WIFI =================
#define ACCESSKEY ""
#define WIFISSID "ball"
#define PASSWORD "tplu1234"

#define projectName "Testing_IOT"
#define deviceName "PA_IOT"

// ================= MQTT =================
const char* mqtt_server = "broker.emqx.io";
const int mqtt_port = 1883;

WiFiClient espClient;
PubSubClient client(espClient);

// ================= TELEGRAM =================
String botToken = "8637281652:AAFmsUcdY_VbknK4TgyQuEfE25vNEKQxwnc";

String chatID = "-1003803563175";

// ================= PIN =================
#define TRIG 5
#define ECHO 18

#define BUZZER 13

#define DHTPIN 25
#define DHTTYPE DHT22

// ================= OBJECT =================
AntaresESPHTTP antares(ACCESSKEY);

DHT dht(DHTPIN, DHTTYPE);

// ================= VARIABLE =================
long duration;
float distance;
float suhu;

bool notifSent = false;
bool distanceNotifSent = false;

unsigned long lastMQTT = 0;
unsigned long lastAntares = 0;

// ================= WIFI =================
void connectWiFi() {

  if (WiFi.status() == WL_CONNECTED) {
    return;
  }

  Serial.print("Connecting WiFi");

  WiFi.disconnect(true);
  WiFi.begin(WIFISSID, PASSWORD);

  while (WiFi.status() != WL_CONNECTED) {

    delay(500);
    Serial.print(".");
  }

  Serial.println("\nWiFi Connected");
  Serial.println(WiFi.localIP());
}

// ================= MQTT CALLBACK =================
void callback(char* topic,
              byte* payload,
              unsigned int length) {

  String message;

  for (int i = 0; i < length; i++) {

    message += (char)payload[i];
  }

  Serial.print("Topic: ");
  Serial.println(topic);

  Serial.print("Message: ");
  Serial.println(message);
}

// ================= MQTT RECONNECT =================
void reconnectMQTT() {

  while (!client.connected()) {

    Serial.println("Connecting MQTT...");

    String clientId = "ESP32-";
    clientId += String(random(0xffff), HEX);

    if (client.connect(clientId.c_str())) {

      Serial.println("MQTT Connected");

    } else {

      Serial.print("MQTT Failed: ");
      Serial.println(client.state());

      delay(2000);
    }
  }
}

// ================= TELEGRAM =================
void sendTelegram(String message) {

  if (WiFi.status() == WL_CONNECTED) {

    HTTPClient http;

    message.replace(" ", "%20");
    message.replace("\n", "%0A");

    String url =
      "https://api.telegram.org/bot" + botToken +
      "/sendMessage?chat_id=" + chatID +
      "&text=" + message;

    http.begin(url);

    int httpResponseCode = http.GET();

    http.end();
  }
}

// ================= SETUP =================
void setup() {

  Serial.begin(115200);

  pinMode(TRIG, OUTPUT);
  pinMode(ECHO, INPUT);

  pinMode(BUZZER, OUTPUT);

  // DHT
  dht.begin();

  // WiFi
  connectWiFi();

  // MQTT
  client.setServer(
    mqtt_server,
    mqtt_port
  );

  client.setCallback(callback);

  // Antares
  antares.setDebug(false);

  antares.wifiConnection(
    WIFISSID,
    PASSWORD
  );

  Serial.println("System Ready");
}

// ================= LOOP =================
void loop() {

  // Reconnect WiFi
  connectWiFi();

  // Reconnect MQTT
  if (!client.connected()) {

    reconnectMQTT();
  }

  client.loop();

  // ================= ULTRASONIC =================
  digitalWrite(TRIG, LOW);
  delayMicroseconds(2);

  digitalWrite(TRIG, HIGH);
  delayMicroseconds(10);

  digitalWrite(TRIG, LOW);

  duration =
    pulseIn(ECHO, HIGH, 30000);

  if (duration == 0) {

    distance = 999;

  } else {

    distance =
      duration * 0.034 / 2;
  }

  // ================= DHT =================
  suhu = dht.readTemperature();

  if (isnan(suhu)) {

    suhu = 0;
  }

  // ================= BUZZER =================
  if (distance > 100) {

      tone(BUZZER, 1000);
      delay(200);
      noTone(BUZZER);

    } else if (distance > 30) {

      tone(BUZZER, 1500);
      delay(100);
      noTone(BUZZER);

      distanceNotifSent = false;

    } else {

      tone(BUZZER, 2000);
      delay(50);
      noTone(BUZZER);

      if (!distanceNotifSent) {

        sendTelegram(
          "WARNING!\nMobil terlalu dekat!\nJarak: " +
          String(distance) +
          " cm"
        );

        distanceNotifSent = true;
      }
    }

  // ================= WARNING SUHU =================
  if (suhu >= 25 && !notifSent) {

    sendTelegram(
      "Suhu garasi tinggi: " +
      String(suhu) +
      " C"
    );

    notifSent = true;
  }

  if (suhu < 25) {

    notifSent = false;
  }

  // ================= MQTT REALTIME =================
  if (millis() - lastMQTT > 2000) {

    lastMQTT = millis();

    // Pastikan baris ini ada: mendeklarasikan variabel waktuMulaiMQTT
    unsigned long waktuMulaiMQTT = millis();

    client.publish(
      "garage/suhu",
      String(suhu).c_str()
    );

    client.publish(
      "garage/jarak",
      String(distance).c_str()
    );

    // Hitung latensi
    unsigned long latensiMQTT = millis() - waktuMulaiMQTT;

    Serial.println("MQTT Publish Success");
    Serial.print(latensiMQTT);
    Serial.println(" ms");
  }

  // ================= ANTARES CLOUD =================
  if (millis() - lastAntares > 10000) {

    lastAntares = millis();

    antares.add("suhu", suhu);
    antares.add("jarak", distance);

    antares.send(
      projectName,
      deviceName
    );

    Serial.println("Antares Upload Success");
  }

  // ================= SERIAL =================
  Serial.print("Jarak: ");
  Serial.print(distance);

  Serial.print(" cm | Suhu: ");
  Serial.println(suhu);

  delay(1000);
}
