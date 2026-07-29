using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace ArgentinaFivePets
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            bool created;
            using (Mutex mutex = new Mutex(true, "ArgentinaFivePetsOverlay_67D1A1E9", out created))
            {
                if (!created)
                {
                    MessageBox.Show(
                        "The five pets are already running.\nUse the paw icon in the system tray to control them.",
                        "Argentina Five Pets",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Information);
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new PetOverlayForm());
            }
        }
    }

    internal sealed class PetOverlayForm : Form
    {
        private const int CellWidth = 192;
        private const int CellHeight = 208;
        private const int DisplayWidth = 132;
        private const int DisplayHeight = 143;
        private const int WsExTransparent = 0x00000020;
        private const int WsExToolWindow = 0x00000080;
        private const int WsExLayered = 0x00080000;
        private const int WsExNoActivate = 0x08000000;
        private static readonly Color TransparentKeyColor = Color.FromArgb(1, 2, 3);

        private readonly List<Pet> pets = new List<Pet>();
        private readonly List<Rectangle> obstacles = new List<Rectangle>();
        private readonly Random random = new Random();
        private readonly Font speechFont = new Font("Microsoft YaHei UI", 11f, FontStyle.Bold);
        private readonly System.Windows.Forms.Timer timer;
        private readonly Stopwatch clock = Stopwatch.StartNew();
        private readonly NotifyIcon trayIcon;
        private PetControllerForm controller;
        private long previousTicks;
        private float obstacleRefreshRemaining;
        private float messiSpeechRemaining;
        private float messiSpeechCooldown;
        private bool useSpanishSpeech;
        private bool paused;

        public PetOverlayForm()
        {
            Rectangle virtualScreen = SystemInformation.VirtualScreen;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Bounds = virtualScreen;
            Text = "Argentina Five Pets Overlay";
            BackColor = TransparentKeyColor;
            TransparencyKey = TransparentKeyColor;
            TopMost = true;
            ShowInTaskbar = false;
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.SupportsTransparentBackColor, true);

            LoadPets();
            pets[1].Enabled = false;
            ScatterPets();

            ContextMenuStrip menu = new ContextMenuStrip();
            ToolStripMenuItem playersMenu = new ToolStripMenuItem("Players");
            for (int playerIndex = 0; playerIndex < pets.Count; playerIndex++)
            {
                int capturedIndex = playerIndex;
                ToolStripMenuItem playerItem = new ToolStripMenuItem(pets[playerIndex].Name);
                playerItem.CheckOnClick = true;
                playerItem.Checked = pets[playerIndex].Enabled;
                playerItem.Click += delegate
                {
                    SetPetEnabled(capturedIndex, playerItem.Checked);
                };
                playersMenu.DropDownItems.Add(playerItem);
            }
            ToolStripMenuItem languageMenu = new ToolStripMenuItem("Language / 语言");
            ToolStripMenuItem chineseLanguageItem = new ToolStripMenuItem("中文");
            ToolStripMenuItem spanishLanguageItem = new ToolStripMenuItem("Español");
            chineseLanguageItem.Checked = true;
            chineseLanguageItem.Click += delegate
            {
                useSpanishSpeech = false;
                chineseLanguageItem.Checked = true;
                spanishLanguageItem.Checked = false;
            };
            spanishLanguageItem.Click += delegate
            {
                useSpanishSpeech = true;
                chineseLanguageItem.Checked = false;
                spanishLanguageItem.Checked = true;
            };
            languageMenu.DropDownItems.Add(chineseLanguageItem);
            languageMenu.DropDownItems.Add(spanishLanguageItem);
            ToolStripMenuItem pauseItem = new ToolStripMenuItem("Pause / Resume");
            pauseItem.Click += delegate { paused = !paused; };
            ToolStripMenuItem controlItem = new ToolStripMenuItem("Manual Controller...");
            controlItem.Click += delegate { ShowController(); };
            ToolStripMenuItem scatterItem = new ToolStripMenuItem("Scatter Now");
            scatterItem.Click += delegate { ScatterPets(); };
            ToolStripMenuItem exitItem = new ToolStripMenuItem("Exit");
            exitItem.Click += delegate { Close(); };
            menu.Items.Add(controlItem);
            menu.Items.Add(playersMenu);
            menu.Items.Add(languageMenu);
            menu.Items.Add(pauseItem);
            menu.Items.Add(scatterItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(exitItem);

            trayIcon = new NotifyIcon();
            trayIcon.Icon = SystemIcons.Application;
            trayIcon.Text = "Argentina Five Pets";
            trayIcon.ContextMenuStrip = menu;
            trayIcon.Visible = true;

            timer = new System.Windows.Forms.Timer();
            timer.Interval = 33;
            timer.Tick += OnTick;
            previousTicks = clock.ElapsedTicks;
            timer.Start();
        }

        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= WsExTransparent | WsExToolWindow | WsExLayered | WsExNoActivate;
                return cp;
            }
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            timer.Stop();
            if (controller != null)
                controller.CloseCompletely();
            trayIcon.Visible = false;
            trayIcon.Dispose();
            foreach (Pet pet in pets)
                pet.Sprite.Dispose();
            speechFont.Dispose();
            base.OnFormClosed(e);
        }

        private void ShowController()
        {
            if (controller == null || controller.IsDisposed)
                controller = new PetControllerForm(this);
            controller.Show();
            controller.BringToFront();
            controller.Activate();
        }

        internal string[] GetPetNames()
        {
            string[] names = new string[pets.Count];
            for (int i = 0; i < pets.Count; i++)
                names[i] = pets[i].Name;
            return names;
        }

        private void SetPetEnabled(int index, bool enabled)
        {
            if (index < 0 || index >= pets.Count)
                return;
            Pet pet = pets[index];
            pet.Enabled = enabled;
            pet.ManualControl = false;
            pet.SpecialRow = -1;
            if (enabled)
            {
                pet.X = 20f + (float)random.NextDouble() * Math.Max(1, ClientSize.Width - DisplayWidth - 40);
                pet.Y = 20f + (float)random.NextDouble() * Math.Max(1, ClientSize.Height - DisplayHeight - 40);
                double angle = random.NextDouble() * Math.PI * 2.0;
                pet.VX = (float)Math.Cos(angle) * 65f;
                pet.VY = (float)Math.Sin(angle) * 65f;
                pet.BehaviorRemaining = 1.5f;
            }
            else
            {
                pet.VX = 0;
                pet.VY = 0;
            }
            Invalidate();
        }

        internal void SetManualVelocity(int index, float x, float y)
        {
            if (index < 0 || index >= pets.Count)
                return;
            Pet pet = pets[index];
            float length = (float)Math.Sqrt(x * x + y * y);
            if (length > 0)
            {
                const float manualSpeed = 145f;
                pet.VX = x / length * manualSpeed;
                pet.VY = y / length * manualSpeed;
            }
            else
            {
                pet.VX = 0;
                pet.VY = 0;
            }
            pet.ManualControl = true;
            pet.SpecialRow = -1;
            pet.BehaviorRemaining = 0.5f;
            pet.Row = pet.VX >= 0 ? 1 : 2;
        }

        internal void StopManualControl(int index)
        {
            if (index < 0 || index >= pets.Count)
                return;
            Pet pet = pets[index];
            pet.VX = 0;
            pet.VY = 0;
            pet.ManualControl = false;
            pet.SpecialRow = 0;
            pet.BehaviorRemaining = 0.45f;
            pet.Row = 0;
        }

        internal void TriggerPlay(int index)
        {
            if (index < 0 || index >= pets.Count)
                return;
            Pet pet = pets[index];
            pet.ManualControl = false;
            pet.VX = 0;
            pet.VY = 0;
            pet.SpecialRow = 7;
            pet.BehaviorRemaining = 1.8f;
            pet.Frame = 0;
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.CompositingMode = CompositingMode.SourceOver;
            e.Graphics.CompositingQuality = CompositingQuality.HighQuality;
            e.Graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
            e.Graphics.PixelOffsetMode = PixelOffsetMode.Half;
            e.Graphics.SmoothingMode = SmoothingMode.HighQuality;

            foreach (Pet pet in pets)
            {
                if (!pet.Enabled)
                    continue;
                int frameCount = GetFrameCount(pet.Row);
                int column = pet.Frame % frameCount;
                RectangleF source = new RectangleF(
                    column * CellWidth,
                    pet.Row * CellHeight,
                    CellWidth,
                    CellHeight);
                RectangleF destination = new RectangleF(
                    pet.X,
                    pet.Y,
                    DisplayWidth,
                    DisplayHeight);
                e.Graphics.DrawImage(
                    pet.Sprite,
                    destination,
                    source,
                    GraphicsUnit.Pixel);
            }

            if (messiSpeechRemaining > 0 && pets.Count > 0 && pets[0].Enabled)
                DrawMessiSpeech(e.Graphics, pets[0]);
        }

        private void DrawMessiSpeech(Graphics graphics, Pet messi)
        {
            const float bubbleWidth = 206f;
            const float bubbleHeight = 42f;
            float bubbleX = messi.X + DisplayWidth * 0.5f - bubbleWidth * 0.5f;
            bubbleX = Math.Max(5f, Math.Min(bubbleX, ClientSize.Width - bubbleWidth - 5f));
            bool drawAbove = messi.Y >= bubbleHeight + 12f;
            float bubbleY = drawAbove ? messi.Y - bubbleHeight - 8f : messi.Y + DisplayHeight + 7f;
            bubbleY = Math.Max(5f, Math.Min(bubbleY, ClientSize.Height - bubbleHeight - 5f));

            RectangleF bubble = new RectangleF(bubbleX, bubbleY, bubbleWidth, bubbleHeight);
            using (SolidBrush white = new SolidBrush(Color.White))
            using (Pen outline = new Pen(Color.FromArgb(30, 30, 30), 2f))
            using (SolidBrush textBrush = new SolidBrush(Color.FromArgb(20, 20, 20)))
            using (StringFormat format = new StringFormat())
            {
                graphics.FillEllipse(white, bubble);
                graphics.DrawEllipse(outline, bubble);

                float tailCenter = Math.Max(bubbleX + 25f, Math.Min(messi.X + DisplayWidth * 0.5f, bubbleX + bubbleWidth - 25f));
                PointF[] tail;
                if (drawAbove)
                {
                    tail = new PointF[]
                    {
                        new PointF(tailCenter - 8f, bubble.Bottom - 5f),
                        new PointF(tailCenter + 8f, bubble.Bottom - 5f),
                        new PointF(messi.X + DisplayWidth * 0.5f, messi.Y + 5f)
                    };
                }
                else
                {
                    tail = new PointF[]
                    {
                        new PointF(tailCenter - 8f, bubble.Top + 5f),
                        new PointF(tailCenter + 8f, bubble.Top + 5f),
                        new PointF(messi.X + DisplayWidth * 0.5f, messi.Y + DisplayHeight - 5f)
                    };
                }
                graphics.FillPolygon(white, tail);
                graphics.DrawLines(outline, tail);

                format.Alignment = StringAlignment.Center;
                format.LineAlignment = StringAlignment.Center;
                string speechText = useSpanishSpeech ? "¿Qué mirás, bobo?" : "给你俩窝窝";
                graphics.DrawString(speechText, speechFont, textBrush, bubble, format);
            }
        }

        private void LoadPets()
        {
            string assetDirectory = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "assets");
            AddPet("Messi", Path.Combine(assetDirectory, "messi.png"));
            AddPet("Enzo", Path.Combine(assetDirectory, "enzo.png"));
            AddPet("Romero", Path.Combine(assetDirectory, "romero.png"));
            AddPet("Lisandro", Path.Combine(assetDirectory, "lisandro.png"));
            AddPet("Paredes", Path.Combine(assetDirectory, "paredes.png"));
        }

        private void AddPet(string name, string path)
        {
            if (!File.Exists(path))
                throw new FileNotFoundException("Missing pet spritesheet: " + path);
            pets.Add(new Pet(name, LoadCleanSprite(path)));
        }

        private static Bitmap LoadCleanSprite(string path)
        {
            using (Bitmap source = new Bitmap(path))
            {
                Bitmap cleaned = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb);
                using (Graphics graphics = Graphics.FromImage(cleaned))
                {
                    graphics.CompositingMode = CompositingMode.SourceCopy;
                    graphics.DrawImageUnscaled(source, 0, 0);
                }

                Rectangle bounds = new Rectangle(0, 0, cleaned.Width, cleaned.Height);
                BitmapData data = cleaned.LockBits(bounds, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
                int byteCount = Math.Abs(data.Stride) * data.Height;
                byte[] pixels = new byte[byteCount];
                Marshal.Copy(data.Scan0, pixels, 0, byteCount);

                for (int y = 0; y < data.Height; y++)
                {
                    int rowOffset = y * Math.Abs(data.Stride);
                    for (int x = 0; x < data.Width; x++)
                    {
                        int alphaOffset = rowOffset + x * 4 + 3;
                        byte alpha = pixels[alphaOffset];
                        pixels[alphaOffset] = alpha < 52 ? (byte)0 : (byte)255;
                    }
                }

                Marshal.Copy(pixels, 0, data.Scan0, byteCount);
                cleaned.UnlockBits(data);
                return cleaned;
            }
        }

        private void ScatterPets()
        {
            float[,] anchors =
            {
                { 0.08f, 0.16f },
                { 0.72f, 0.12f },
                { 0.18f, 0.65f },
                { 0.74f, 0.66f },
                { 0.45f, 0.40f }
            };

            for (int i = 0; i < pets.Count; i++)
            {
                Pet pet = pets[i];
                if (!pet.Enabled)
                    continue;
                pet.X = anchors[i, 0] * Math.Max(1, ClientSize.Width - DisplayWidth);
                pet.Y = anchors[i, 1] * Math.Max(1, ClientSize.Height - DisplayHeight);
                double angle = random.NextDouble() * Math.PI * 2.0;
                float speed = 45f + (float)random.NextDouble() * 35f;
                pet.VX = (float)Math.Cos(angle) * speed;
                pet.VY = (float)Math.Sin(angle) * speed;
                pet.BehaviorRemaining = 1.5f + (float)random.NextDouble() * 2f;
                pet.SpecialRow = -1;
                pet.Frame = random.Next(0, 6);
                pet.Row = pet.VX >= 0 ? 1 : 2;
            }
            Invalidate();
        }

        private void OnTick(object sender, EventArgs e)
        {
            long now = clock.ElapsedTicks;
            float dt = (float)(now - previousTicks) / Stopwatch.Frequency;
            previousTicks = now;
            if (dt > 0.08f)
                dt = 0.08f;
            if (paused)
                return;

            messiSpeechRemaining = Math.Max(0, messiSpeechRemaining - dt);
            messiSpeechCooldown = Math.Max(0, messiSpeechCooldown - dt);
            obstacleRefreshRemaining -= dt;
            if (obstacleRefreshRemaining <= 0)
            {
                RefreshWindowObstacles();
                obstacleRefreshRemaining = 0.7f;
            }

            UpdateBehaviors(dt);
            ApplySeparation(dt);

            foreach (Pet pet in pets)
            {
                if (!pet.Enabled)
                    continue;
                float nextX = pet.X + pet.VX * dt;
                float nextY = pet.Y + pet.VY * dt;
                ResolveScreenEdges(pet, ref nextX, ref nextY);
                ResolveWindowObstacles(pet, ref nextX, ref nextY);
                pet.X = nextX;
                pet.Y = nextY;

                pet.AnimationAccumulator += dt;
                if (pet.AnimationAccumulator >= 0.12f)
                {
                    pet.AnimationAccumulator -= 0.12f;
                    pet.Frame = (pet.Frame + 1) % GetFrameCount(pet.Row);
                }
            }

            ResolveOverlaps();
            Invalidate();
        }

        private void UpdateBehaviors(float dt)
        {
            foreach (Pet pet in pets)
            {
                if (!pet.Enabled)
                    continue;
                if (pet.ManualControl)
                {
                    pet.SpecialRow = -1;
                    pet.Row = pet.VX >= 0 ? 1 : 2;
                    continue;
                }

                pet.BehaviorRemaining -= dt;
                if (pet.BehaviorRemaining <= 0)
                {
                    int choice = random.Next(100);
                    if (choice < 18)
                    {
                        pet.SpecialRow = 7;
                        pet.VX = 0;
                        pet.VY = 0;
                        pet.BehaviorRemaining = 1.2f + (float)random.NextDouble() * 1.4f;
                    }
                    else if (choice < 28)
                    {
                        pet.SpecialRow = 3;
                        pet.VX = 0;
                        pet.VY = 0;
                        pet.BehaviorRemaining = 0.9f + (float)random.NextDouble();
                    }
                    else if (choice < 38)
                    {
                        pet.SpecialRow = 4;
                        pet.VX = 0;
                        pet.VY = 0;
                        pet.BehaviorRemaining = 0.8f + (float)random.NextDouble() * 0.7f;
                    }
                    else
                    {
                        pet.SpecialRow = -1;
                        double angle = random.NextDouble() * Math.PI * 2.0;
                        float speed = 42f + (float)random.NextDouble() * 48f;
                        pet.VX = (float)Math.Cos(angle) * speed;
                        pet.VY = (float)Math.Sin(angle) * speed;
                        pet.BehaviorRemaining = 1.8f + (float)random.NextDouble() * 3.2f;
                    }
                    pet.Frame = 0;
                }

                if (pet.SpecialRow >= 0)
                    pet.Row = pet.SpecialRow;
                else
                    pet.Row = pet.VX >= 0 ? 1 : 2;
            }
        }

        private void ApplySeparation(float dt)
        {
            const float preferredDistance = 158f;
            for (int i = 0; i < pets.Count; i++)
            {
                for (int j = i + 1; j < pets.Count; j++)
                {
                    Pet a = pets[i];
                    Pet b = pets[j];
                    if (!a.Enabled || !b.Enabled)
                        continue;
                    float ax = a.X + DisplayWidth * 0.5f;
                    float ay = a.Y + DisplayHeight * 0.5f;
                    float bx = b.X + DisplayWidth * 0.5f;
                    float by = b.Y + DisplayHeight * 0.5f;
                    float dx = ax - bx;
                    float dy = ay - by;
                    float distanceSquared = dx * dx + dy * dy;
                    if (distanceSquared >= preferredDistance * preferredDistance)
                        continue;

                    float distance = (float)Math.Sqrt(Math.Max(1f, distanceSquared));
                    if (distance < 2f)
                    {
                        dx = i % 2 == 0 ? 1f : -1f;
                        dy = j % 2 == 0 ? 0.7f : -0.7f;
                        distance = (float)Math.Sqrt(dx * dx + dy * dy);
                    }
                    float strength = (preferredDistance - distance) * 2.4f * dt;
                    float nx = dx / distance;
                    float ny = dy / distance;
                    a.VX += nx * strength;
                    a.VY += ny * strength;
                    b.VX -= nx * strength;
                    b.VY -= ny * strength;
                    LimitSpeed(a, 105f);
                    LimitSpeed(b, 105f);
                }
            }
        }

        private static void LimitSpeed(Pet pet, float maximum)
        {
            float speedSquared = pet.VX * pet.VX + pet.VY * pet.VY;
            if (speedSquared <= maximum * maximum)
                return;
            float scale = maximum / (float)Math.Sqrt(speedSquared);
            pet.VX *= scale;
            pet.VY *= scale;
        }

        private void ResolveOverlaps()
        {
            const float minimumDistance = 136f;
            for (int i = 0; i < pets.Count; i++)
            {
                for (int j = i + 1; j < pets.Count; j++)
                {
                    Pet a = pets[i];
                    Pet b = pets[j];
                    if (!a.Enabled || !b.Enabled)
                        continue;
                    float dx = (a.X + DisplayWidth * 0.5f) - (b.X + DisplayWidth * 0.5f);
                    float dy = (a.Y + DisplayHeight * 0.5f) - (b.Y + DisplayHeight * 0.5f);
                    float distanceSquared = dx * dx + dy * dy;
                    if (distanceSquared >= minimumDistance * minimumDistance)
                        continue;

                    TriggerMessiSpeech(a, b);
                    float distance = (float)Math.Sqrt(Math.Max(1f, distanceSquared));
                    float nx = dx / distance;
                    float ny = dy / distance;
                    float push = (minimumDistance - distance) * 0.5f + 1f;
                    a.X += nx * push;
                    a.Y += ny * push;
                    b.X -= nx * push;
                    b.Y -= ny * push;
                    ClampToScreen(a);
                    ClampToScreen(b);
                }
            }
        }

        private void TriggerMessiSpeech(Pet first, Pet second)
        {
            if (messiSpeechCooldown > 0)
                return;
            if (first.Name != "Messi" && second.Name != "Messi")
                return;
            messiSpeechRemaining = 2.4f;
            messiSpeechCooldown = 5.5f;
        }

        private void ResolveScreenEdges(Pet pet, ref float x, ref float y)
        {
            float maximumX = Math.Max(0, ClientSize.Width - DisplayWidth);
            float maximumY = Math.Max(0, ClientSize.Height - DisplayHeight);
            if (x < 0)
            {
                x = 0;
                pet.VX = Math.Abs(pet.VX);
                EndSpecial(pet);
            }
            else if (x > maximumX)
            {
                x = maximumX;
                pet.VX = -Math.Abs(pet.VX);
                EndSpecial(pet);
            }
            if (y < 0)
            {
                y = 0;
                pet.VY = Math.Abs(pet.VY);
                EndSpecial(pet);
            }
            else if (y > maximumY)
            {
                y = maximumY;
                pet.VY = -Math.Abs(pet.VY);
                EndSpecial(pet);
            }
        }

        private void ResolveWindowObstacles(Pet pet, ref float x, ref float y)
        {
            RectangleF proposed = new RectangleF(x + 18f, y + 16f, DisplayWidth - 36f, DisplayHeight - 25f);
            foreach (Rectangle obstacle in obstacles)
            {
                RectangleF inflated = RectangleF.Inflate(obstacle, 5f, 5f);
                if (!proposed.IntersectsWith(inflated))
                    continue;

                float overlapLeft = proposed.Right - inflated.Left;
                float overlapRight = inflated.Right - proposed.Left;
                float overlapTop = proposed.Bottom - inflated.Top;
                float overlapBottom = inflated.Bottom - proposed.Top;
                float minimum = Math.Min(Math.Min(overlapLeft, overlapRight), Math.Min(overlapTop, overlapBottom));

                if (minimum == overlapLeft)
                {
                    x -= overlapLeft;
                    pet.VX = -Math.Abs(pet.VX);
                }
                else if (minimum == overlapRight)
                {
                    x += overlapRight;
                    pet.VX = Math.Abs(pet.VX);
                }
                else if (minimum == overlapTop)
                {
                    y -= overlapTop;
                    pet.VY = -Math.Abs(pet.VY);
                }
                else
                {
                    y += overlapBottom;
                    pet.VY = Math.Abs(pet.VY);
                }

                EndSpecial(pet);
                proposed = new RectangleF(x + 18f, y + 16f, DisplayWidth - 36f, DisplayHeight - 25f);
            }
        }

        private static void EndSpecial(Pet pet)
        {
            pet.SpecialRow = -1;
            pet.BehaviorRemaining = Math.Min(pet.BehaviorRemaining, 0.4f);
        }

        private void ClampToScreen(Pet pet)
        {
            pet.X = Math.Max(0, Math.Min(pet.X, ClientSize.Width - DisplayWidth));
            pet.Y = Math.Max(0, Math.Min(pet.Y, ClientSize.Height - DisplayHeight));
        }

        private static int GetFrameCount(int row)
        {
            switch (row)
            {
                case 0: return 6;
                case 1: return 8;
                case 2: return 8;
                case 3: return 4;
                case 4: return 5;
                case 5: return 8;
                case 6: return 6;
                case 7: return 6;
                case 8: return 6;
                case 9: return 8;
                case 10: return 8;
                default: return 6;
            }
        }

        private void RefreshWindowObstacles()
        {
            obstacles.Clear();
            int ownProcessId = Process.GetCurrentProcess().Id;
            Rectangle virtualScreen = SystemInformation.VirtualScreen;
            long virtualArea = (long)Math.Max(1, virtualScreen.Width) * Math.Max(1, virtualScreen.Height);

            EnumWindows(delegate(IntPtr handle, IntPtr parameter)
            {
                if (!IsWindowVisible(handle) || IsIconic(handle))
                    return true;

                int processId;
                GetWindowThreadProcessId(handle, out processId);
                if (processId == ownProcessId)
                    return true;

                int cloaked = 0;
                DwmGetWindowAttribute(handle, 14, out cloaked, Marshal.SizeOf(typeof(int)));
                if (cloaked != 0)
                    return true;

                NativeRect nativeRect;
                if (!GetWindowRect(handle, out nativeRect))
                    return true;
                Rectangle rectangle = Rectangle.FromLTRB(
                    nativeRect.Left - virtualScreen.Left,
                    nativeRect.Top - virtualScreen.Top,
                    nativeRect.Right - virtualScreen.Left,
                    nativeRect.Bottom - virtualScreen.Top);
                if (rectangle.Width < 120 || rectangle.Height < 80)
                    return true;
                if ((long)rectangle.Width * rectangle.Height > virtualArea * 82 / 100)
                    return true;
                if (!rectangle.IntersectsWith(new Rectangle(0, 0, ClientSize.Width, ClientSize.Height)))
                    return true;

                obstacles.Add(rectangle);
                return true;
            }, IntPtr.Zero);
        }

        private delegate bool EnumWindowsProc(IntPtr handle, IntPtr parameter);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr handle);

        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr handle);

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr handle, out NativeRect rectangle);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr handle, out int processId);

        [DllImport("dwmapi.dll")]
        private static extern int DwmGetWindowAttribute(
            IntPtr handle,
            int attribute,
            out int value,
            int valueSize);

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeRect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }
    }

    internal sealed class Pet
    {
        public readonly string Name;
        public readonly Bitmap Sprite;
        public float X;
        public float Y;
        public float VX;
        public float VY;
        public int Row;
        public int Frame;
        public int SpecialRow = -1;
        public float BehaviorRemaining;
        public float AnimationAccumulator;
        public bool ManualControl;
        public bool Enabled = true;

        public Pet(string name, Bitmap sprite)
        {
            Name = name;
            Sprite = sprite;
        }
    }

    internal sealed class PetControllerForm : Form
    {
        private readonly PetOverlayForm overlay;
        private readonly ComboBox petSelector;
        private readonly HashSet<Keys> pressedKeys = new HashSet<Keys>();
        private bool allowClose;

        public PetControllerForm(PetOverlayForm overlayForm)
        {
            overlay = overlayForm;
            Text = "Argentina Pets - Manual Control";
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            StartPosition = FormStartPosition.CenterScreen;
            TopMost = true;
            ShowInTaskbar = false;
            ClientSize = new Size(360, 238);
            KeyPreview = true;

            Label selectLabel = new Label();
            selectLabel.Text = "Choose player:";
            selectLabel.SetBounds(18, 18, 100, 24);
            Controls.Add(selectLabel);

            petSelector = new ComboBox();
            petSelector.DropDownStyle = ComboBoxStyle.DropDownList;
            petSelector.SetBounds(120, 15, 220, 26);
            petSelector.Items.AddRange(overlay.GetPetNames());
            petSelector.SelectedIndex = 0;
            petSelector.SelectedIndexChanged += delegate
            {
                pressedKeys.Clear();
                StopSelected();
            };
            Controls.Add(petSelector);

            Button upButton = CreateDirectionButton("▲", 150, 60, 0, -1);
            Button leftButton = CreateDirectionButton("◀", 95, 110, -1, 0);
            Button stopButton = new Button();
            stopButton.Text = "■";
            stopButton.SetBounds(150, 110, 50, 42);
            stopButton.Click += delegate { StopSelected(); };
            Controls.Add(stopButton);
            Button rightButton = CreateDirectionButton("▶", 205, 110, 1, 0);
            Button downButton = CreateDirectionButton("▼", 150, 160, 0, 1);

            Button playButton = new Button();
            playButton.Text = "Play";
            playButton.SetBounds(260, 82, 78, 42);
            playButton.Click += delegate { overlay.TriggerPlay(petSelector.SelectedIndex); };
            Controls.Add(playButton);

            Label helpLabel = new Label();
            helpLabel.Text = "Hold Arrow keys or W/A/S/D to move. Release to stop.";
            helpLabel.TextAlign = ContentAlignment.MiddleCenter;
            helpLabel.SetBounds(12, 208, 336, 24);
            Controls.Add(helpLabel);

            KeyDown += OnControllerKeyDown;
            KeyUp += OnControllerKeyUp;
            Deactivate += delegate
            {
                pressedKeys.Clear();
                StopSelected();
            };
        }

        protected override bool IsInputKey(Keys keyData)
        {
            Keys key = keyData & Keys.KeyCode;
            if (key == Keys.Left || key == Keys.Right || key == Keys.Up || key == Keys.Down)
                return true;
            return base.IsInputKey(keyData);
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            pressedKeys.Clear();
            StopSelected();
            if (!allowClose && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                Hide();
                return;
            }
            base.OnFormClosing(e);
        }

        internal void CloseCompletely()
        {
            allowClose = true;
            Close();
        }

        private Button CreateDirectionButton(string text, int x, int y, float directionX, float directionY)
        {
            Button button = new Button();
            button.Text = text;
            button.SetBounds(x, y, 50, 42);
            button.MouseDown += delegate
            {
                overlay.SetManualVelocity(petSelector.SelectedIndex, directionX, directionY);
            };
            button.MouseUp += delegate { StopSelected(); };
            button.MouseLeave += delegate
            {
                if (MouseButtons == MouseButtons.None)
                    StopSelected();
            };
            Controls.Add(button);
            return button;
        }

        private void OnControllerKeyDown(object sender, KeyEventArgs e)
        {
            if (IsMovementKey(e.KeyCode))
            {
                pressedKeys.Add(e.KeyCode);
                UpdateKeyboardVelocity();
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
            else if (e.KeyCode == Keys.Space)
            {
                overlay.TriggerPlay(petSelector.SelectedIndex);
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
        }

        private void OnControllerKeyUp(object sender, KeyEventArgs e)
        {
            if (!IsMovementKey(e.KeyCode))
                return;
            pressedKeys.Remove(e.KeyCode);
            UpdateKeyboardVelocity();
            e.Handled = true;
            e.SuppressKeyPress = true;
        }

        private void UpdateKeyboardVelocity()
        {
            float x = 0;
            float y = 0;
            if (pressedKeys.Contains(Keys.Left) || pressedKeys.Contains(Keys.A))
                x -= 1;
            if (pressedKeys.Contains(Keys.Right) || pressedKeys.Contains(Keys.D))
                x += 1;
            if (pressedKeys.Contains(Keys.Up) || pressedKeys.Contains(Keys.W))
                y -= 1;
            if (pressedKeys.Contains(Keys.Down) || pressedKeys.Contains(Keys.S))
                y += 1;

            if (x == 0 && y == 0)
                StopSelected();
            else
                overlay.SetManualVelocity(petSelector.SelectedIndex, x, y);
        }

        private void StopSelected()
        {
            overlay.StopManualControl(petSelector.SelectedIndex);
        }

        private static bool IsMovementKey(Keys key)
        {
            return key == Keys.Left || key == Keys.Right || key == Keys.Up || key == Keys.Down ||
                   key == Keys.W || key == Keys.A || key == Keys.S || key == Keys.D;
        }
    }
}
