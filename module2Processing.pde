import processing.serial.*;

Serial myPort;

//values from ESP32 in order
int joyX, joyY, joyBtn, pot, popBtn;

//balloon 'state'
float balloonX, balloonY;
float baseW = 100, baseH = 130; //normal size, aka minimum
float balloonW = baseW, balloonH = baseH; //current size, updated each frame 
float maxScale = 3.0;
float currentScale = 1.0;

//balloon colors
color[] palette = {
  color(220, 30, 30), // red starting color
  color(80, 150, 210), // blue
  color(250, 200, 30), //yellow
  color(110, 180, 60), //green
  color(180, 70, 220), // purple
  color(250, 150, 50), // orange
  color(250, 80, 200) // pink
};
int colorIndex = 0;
int prevJoyBtn = 0;

//joystick movement of balloon
float centerX = 1955; //resting values taken from serial monitor
float centerY = 1980;
float deadzone = 50; // for resistance, ignore pushes smaller than this
float maxSpeed = 8; 

//overinflation variables
float safeLimit = 0.8;
float strain = 0; // 0 = relaxed, 1 = pop
float popTime = 2.5; // seconds in danger zone before popping
float recoverTime = 1.0; // seconds to fully relax after deflating 
float maxShake = 8; // pixel shake-age at max strain

//popping (with regular button)
ArrayList<Particle> particles = new ArrayList<Particle>();
boolean popped = false;
int poppedAt = 0;
float respawnDelay = 1.2; //seconds before new balloon appears
int prevPopBtn = 0; //edge detection

//balloon string
int numPoints = 25;
float segLen = 5; //distance between points so they can't all merge together or cross over
float stringGravity = 0.4;
float stringDamping = 0.95;
float[] sx = new float[numPoints]; //current x of each point
float[] sy = new float[numPoints]; //current y
float[] spx = new float[numPoints]; //previous x
float[] spy = new float[numPoints]; //previous y
float shakeX = 0, shakeY = 0; //shake offsets, shared with balloon

void setup() {
  size (800, 600);
  printArray(Serial.list());
  myPort = new Serial(this, Serial.list()[9], 9600);
  myPort.bufferUntil('\n');
  
  balloonX = width/2;
  balloonY = height/2;
  initString();
}

void draw() {
  updateColor();
  updatePop();
  if (!popped) {
    updateInflation(); //balloon inflation on potentiometer
    updateMovement(); //balloon movement on joystick
  }
  updateShake();
  updateString();
  
  drawBackground();
  drawString(); // behind the balloon
  if (!popped) {
    drawBalloon();
  }
  updateParticles();
}

void drawCloud(float x, float y) {
  noStroke();
  fill(255);
  ellipse(x, y, 100, 50); //middle
  ellipse (x-35, y+5, 70, 40); //left
  ellipse(x+35, y+5, 70, 40); //right
  ellipse(x+12, y-10, 60, 45); //extra bump
}
  
void updateColor(){
  //joyBtn is 1 when held. only want to read the moment it becomes 1
  if (joyBtn == 1 && prevJoyBtn == 0) {
    colorIndex = (colorIndex + 1) % palette.length;
  }
  prevJoyBtn = joyBtn;
}

void drawBalloon() {
  float cx = balloonX + shakeX;
  float cy = balloonY + shakeY;
  color base = palette[colorIndex];

  //gradient body, adapted from Processing > Examples > Basics > Color > RadialGradient  
  pushStyle();               
  colorMode(HSB, 360, 100, 100);  
  ellipseMode(RADIUS);                 
  noStroke();                         

  //must come after colorMode
  float h = hue(base);               
  float s = saturation(base);
  float b = brightness(base) * 0.6; // start dark at the edge

  int radiusY = int(balloonH / 2); // like "int radius = dim/2" in radialGradient 
  float stepB = (min(100, brightness(base) * 1.1) - b) / radiusY; // brightness added per ring
  float stepS = -(s * 0.45) / radiusY; // saturation removed per ring

  for (int r = radiusY; r > 0; --r) { // biggest ring first, down to 1
    float t = 1 - r / (float) radiusY; // 0 at edge, near 1 at center
    float rx = r * balloonW / balloonH; 
    fill(h, s, b); 
    ellipse(cx - t * balloonW * 0.18, //center ring toward upper left 
            cy - t * balloonH * 0.20,
            rx, r);
    s += stepS; // update the color each pass
    b += stepB;
  }
  popStyle();                           

  //highlight and knot
  noStroke();
  fill(255, 255, 255, 150);
  ellipse(cx - balloonW * 0.20, cy - balloonH * 0.22,
          balloonW * 0.14, balloonH * 0.20);

  fill(lerpColor(base, color(0), 0.35));
  triangle(cx, cy + balloonH / 2,
           cx - 8, cy + balloonH / 2 + 12,
           cx + 8, cy + balloonH / 2 + 12);
}

void drawBackground() {
  background(135, 206, 235); // sky
  noStroke();
  drawCloud(150, 90);
  drawCloud(450, 150);
  drawCloud(650, 70);
  fill(80, 170, 70); // grass
  rect(0, height*0.8, width, height*0.2);
}


//match order to arduino serial output
void serialEvent(Serial p) {
  String line = p.readStringUntil('\n');
  if (line == null) return;
  String[] parts = split(trim(line), ',');
  if (parts.length == 5) {
    joyX = int(parts[0]);
    joyY = int(parts[1]);
    joyBtn = int(parts[2]);
    pot = int(parts[3]);
    popBtn = int(parts[4]);
  }
}
 
//joystick movement function
float axisToSpeed(float offset) {
  if (abs(offset) < deadzone) return 0; //inside deadzone = no movement
  
  float direction = (offset > 0) ? 1 : -1; 
  float pastDeadzone = abs(offset) - deadzone; //how far beyond the deadzone
  float fraction = constrain(pastDeadzone / (2000 - deadzone), 0, 1); 
    //2000 is a rounded amount of how much more it travels to 4095 from resting value of 1955
  return direction * fraction * maxSpeed;
}

//balloon movement, restrictions
void updateMovement() {
  balloonX += axisToSpeed(joyX - centerX);
  balloonY += axisToSpeed(joyY - centerY);
  
  //keeping the balloon and its knot on the screen
  balloonX = constrain(balloonX, balloonW/2, width-balloonW/2);
  balloonY = constrain(balloonY, balloonH/2, height-balloonH/2-12);
}
  
 
void updateInflation() {
  //accounting for resting state on potentiometer being reversed (4095->0):
  float inflation = constrain(map(pot, 4095, 0, 0, 1), 0, 1);
  
  //size reaches max at safeLimit, then stays there
  float sizeFraction = constrain(inflation / safeLimit, 0, 1);
  float targetScale = lerp(1.0, maxScale, sizeFraction);
  currentScale = lerp(currentScale, targetScale, 0.15);
  
  balloonW = baseW * currentScale;
  balloonH = baseH * currentScale;
  
  //strain -- builds in danger zone and relaxes outside of it
  if (inflation > safeLimit) {
    strain += 1.0 / (frameRate * popTime);
  } else { 
    strain -= 1.0 / (frameRate * recoverTime);
  }
  strain = constrain(strain, 0, 1);
  
  if (strain >= 1) {
    popBalloon();
  }
}

void updateShake() {
  float amount = strain * maxShake;
  shakeX = random(-amount, amount);
  shakeY = random(-amount, amount);
}

//where the string attaches
float anchorX() { return balloonX + shakeX; }
float anchorY() { return balloonY + shakeY + balloonH / 2 + 12; }

void initString() {
  for (int i = 0; i < numPoints; i++) {
    sx[i] = anchorX();
    sy[i] = anchorY() + i * segLen; //hanging straight down
    spx[i] = sx[i];
    spy[i] = sy[i];
  }
}

void updateString() {
  //motion -- each point continues the way it was moving, plus gravity
  for (int i = 0; i < numPoints; i++) {
    if (i == 0 && !popped) continue; 
    float vx = (sx[i] - spx[i]) * stringDamping;
    float vy = (sy[i] - spy[i]) * stringDamping;
    spx[i] = sx[i];
    spy[i] = sy[i];
    sx[i] += vx;
    sy[i] += vy + stringGravity;
  }
  
  //pin top point to knot
  if (!popped) {
    sx[0] = anchorX();
    sy[0] = anchorY();
    spx[0] = sx[0];
    spy[0] = sy[0];
  }
  
  //distance -- for stiffness
  for (int iter = 0; iter < 8; iter++) {
    for (int i = 0; i < numPoints - 1; i++) {
      float dx = sx[i+1] - sx[i];
      float dy = sy[i+1] - sy[i];
      float d = sqrt(dx*dx + dy*dy);
      if (d == 0) continue;
      float diff = (d - segLen) / d;
      
      if (i == 0 && !popped) {
        //top point is pinned, so the next point does the moving
        sx[1] -= dx * diff;
        sy[1] -= dy * diff;
      } else {
        sx[i]     += dx * diff * 0.5;
        sy[i]     += dy * diff * 0.5;
        sx[i + 1] -= dx * diff * 0.5;
        sy[i + 1] -= dy * diff * 0.5;
      }
    }
  }
  
  //keep the string from falling through the floor
  for (int i = 0; i < numPoints; i++) {
     sy[i] = min(sy[i], height - 2);
  }
}

void drawString() {
  stroke(50);
  strokeWeight(2);
  noFill();
  beginShape();
  for (int i = 0; i < numPoints; i++) {
    vertex(sx[i], sy[i]);
  }
  endShape();
  strokeWeight(1);
}

void popBalloon() {
  if (popped) return; 
  
  int count = int(50*currentScale); //bigger balloon, bigger burst
  for (int i = 0; i < count; i++) {
    particles.add(new Particle(balloonX, balloonY, balloonW, balloonH, palette[colorIndex]));
  }
  popped = true;
  poppedAt = millis();
}

void resetBalloon() {
  balloonX = width/2;
  balloonY = height/2;
  currentScale = 1.0;
  balloonW = baseW;
  balloonH = baseH;
  //colorIndex = 0; //back to red
  strain = 0;
  popped = false;
  shakeX = 0;
  shakeY = 0;
  initString();
}

void updatePop() {
  //pop button should only act on the moment it 'becomes' pressed
  if (popBtn == 1 && prevPopBtn == 0) {
    popBalloon();
  }
  prevPopBtn = popBtn;
  
  //respawn after delay
  if (popped && millis() - poppedAt > respawnDelay * 1000) {
    resetBalloon();
  }
}

void updateParticles() {
  for (int i = particles.size() - 1; i >= 0; i--) { //backwards
    Particle p = particles.get(i);
    p.update();
    p.display();
    if (p.isDead()) {
      particles.remove(i);
    }
  }
}
 
  
 //particles for popping animation 
class Particle {
  float x, y; 
  float vx, vy; // velocity
  float size;
  float life; // 255 = fully visible, 0 = gone
  color c;
  
  Particle(float cx, float cy, float w, float h, color c) {
    this.c = c;
    
    float angle = random(TWO_PI); //random direction 
    float reach = random(0.6, 1.0); //0.6 inside the balloon, 1.0 on its edge
    
    //offset from the center, shaped like the balloon
    float offsetX = cos(angle) * (w/2) * reach;
    float offsetY = sin(angle) * (h/2) * reach;
    
    x = cx + offsetX;
    y = cy + offsetY;
    
    //fly outward in proportion to offset
    float k = random(0.06, 0.14); 
    vx = offsetX * k + random(-0.5, 0.5);
    vy = offsetY * k + random(-0.5, 0.5);
    
    size = random(4, 11);
    life = 255; 
  }
  
  void update() {
    vy += 0.06; // gravity to pull them down, weak
    vx *= 0.95; // slight air drag, maybe NOT
    vy *= 0.95;
    x += vx;
    y += vy;
    life -= 3; // fade out
  }
  
  void display() {
    noStroke();
    fill(c, life); //same color
    ellipse(x, y, size, size);
  }
  
  boolean isDead() {
    return life <= 0;
  }
}
  
