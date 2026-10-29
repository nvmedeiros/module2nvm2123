
//serial output order: joyX, joyY, joyBtn, pot, button
const int joyXPin = 32;
const int joyYPin = 39;
const int joyButtonPin = 33;
const int potPin = 36;
const int buttonPin = 2;

void setup() {
  Serial.begin(9600);

  pinMode(joyButtonPin, INPUT_PULLUP);
  pinMode(buttonPin, INPUT_PULLUP);
}

void loop() {
  int xValue = analogRead(joyXPin); // 0 to 4095
  int yValue = analogRead(joyYPin); // 0 to 4095
  int potValue = analogRead(potPin); // 4095 to 0

  // 1 for pressed, 0 for released
  int joyBtn = !digitalRead(joyButtonPin);
  int popBtn = !digitalRead(buttonPin);

  // Send values to Processing, separated by commas
  Serial.print(xValue);
  Serial.print(",");
  Serial.print(yValue);
  Serial.print(",");
  Serial.print(joyBtn);
  Serial.print(",");
  Serial.print(potValue);
  Serial.print(",");
  Serial.println(popBtn);

  delay(50);
}
