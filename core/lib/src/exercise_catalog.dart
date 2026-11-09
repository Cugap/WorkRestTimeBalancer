import 'exercise.dart';

/// Локальный набор упражнений (30 штук). Категории чередуются, поэтому
/// упражнения по кругу не повторяют одну и ту же часть тела подряд.
const List<Exercise> exerciseCatalog = <Exercise>[
  Exercise(
    id: 'eyes-palming',
    name: 'Пальминг',
    description:
        'Закройте глаза и накройте их ладонями без давления. Посидите в '
        'темноте, пока глаза не расслабятся.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.eyes,
  ),
  Exercise(
    id: 'hands-lock',
    name: 'Замок',
    description:
        'Сцепите пальцы в замок, вытяните руки вперёд ладонями наружу и '
        'потянитесь.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.hands,
  ),
  Exercise(
    id: 'body-head-tilt',
    name: 'Наклоны головы',
    description:
        'Наклоните голову к правому плечу, задержитесь, затем плавно '
        'переведите к левому.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.body,
  ),
  Exercise(
    id: 'eyes-far-look',
    name: 'Взгляд вдаль',
    description:
        'Найдите за окном самый далёкий предмет и рассматривайте его, не '
        'напрягая глаза.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.eyes,
  ),
  Exercise(
    id: 'hands-rotate',
    name: 'Вращение кистей',
    description:
        'Вращайте кистями по кругу сначала в одну сторону, затем в другую.',
    duration: Duration(seconds: 25),
    category: ExerciseCategory.hands,
  ),
  Exercise(
    id: 'body-head-turn',
    name: 'Повороты головы',
    description:
        'Поверните голову вправо до упора, задержитесь и так же плавно '
        'поверните влево.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.body,
  ),
  Exercise(
    id: 'eyes-clock',
    name: 'Часовые стрелки',
    description:
        'Медленно переводите взгляд по кругу: вверх, вправо, вниз, влево. '
        'Голова неподвижна.',
    duration: Duration(seconds: 25),
    category: ExerciseCategory.eyes,
  ),
  Exercise(
    id: 'hands-fists',
    name: 'Кулаки',
    description:
        'Сожмите кулаки на пару секунд и разожмите, растопырив пальцы как '
        'можно шире.',
    duration: Duration(seconds: 20),
    category: ExerciseCategory.hands,
  ),
  Exercise(
    id: 'body-shoulders-up',
    name: 'Плечи вверх',
    description:
        'Поднимите плечи к ушам, задержите на пару секунд и резко опустите.',
    duration: Duration(seconds: 20),
    category: ExerciseCategory.body,
  ),
  Exercise(
    id: 'eyes-blink',
    name: 'Частое моргание',
    description:
        'Поморгайте без усилия, затем закройте глаза и дайте им отдохнуть.',
    duration: Duration(seconds: 20),
    category: ExerciseCategory.eyes,
  ),
  Exercise(
    id: 'hands-finger-pull',
    name: 'Растяжка пальцев',
    description:
        'Мягко отгибайте пальцы назад по одному, задерживаясь на пару секунд.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.hands,
  ),
  Exercise(
    id: 'body-shoulder-circles',
    name: 'Вращение плечами',
    description:
        'Вращайте плечами назад большими кругами, затем вперёд.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.body,
  ),
  Exercise(
    id: 'eyes-figure-eight',
    name: 'Восьмёрка',
    description:
        'Рисуйте взглядом горизонтальную восьмёрку на стене перед собой.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.eyes,
  ),
  Exercise(
    id: 'hands-eight',
    name: 'Восьмёрка кистями',
    description:
        'Опишите кистями большую восьмёрку перед собой, работая только '
        'запястьями.',
    duration: Duration(seconds: 25),
    category: ExerciseCategory.hands,
  ),
  Exercise(
    id: 'body-back-arch',
    name: 'Прогиб в спине',
    description:
        'Сядьте ровно, положите руки на поясницу и мягко прогнитесь назад.',
    duration: Duration(seconds: 25),
    category: ExerciseCategory.body,
  ),
  Exercise(
    id: 'eyes-left-right',
    name: 'Влево-вправо',
    description:
        'Переводите взгляд от крайней левой точки к крайней правой и '
        'обратно, не поворачивая голову.',
    duration: Duration(seconds: 25),
    category: ExerciseCategory.eyes,
  ),
  Exercise(
    id: 'hands-wrists',
    name: 'Разминка запястий',
    description:
        'Согните кисти вверх и вниз, помогая другой рукой, по несколько раз.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.hands,
  ),
  Exercise(
    id: 'body-twist',
    name: 'Повороты корпуса',
    description:
        'Сидя поверните корпус вправо, держась за спинку стула, затем влево.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.body,
  ),
  Exercise(
    id: 'eyes-up-down',
    name: 'Вверх-вниз',
    description:
        'Поднимите взгляд к потолку, задержите, опустите к полу и снова '
        'поднимите.',
    duration: Duration(seconds: 25),
    category: ExerciseCategory.eyes,
  ),
  Exercise(
    id: 'hands-palms',
    name: 'Массаж ладоней',
    description:
        'Разотрите ладони друг о друга, затем помассируйте основание большого '
        'пальца.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.hands,
  ),
  Exercise(
    id: 'body-fold',
    name: 'Наклон вперёд',
    description:
        'Встаньте и мягко наклонитесь вперёд, позволяя рукам свободно '
        'свисать.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.body,
  ),
  Exercise(
    id: 'eyes-nose',
    name: 'Взгляд на кончик носа',
    description:
        'Сведите взгляд к кончику носа, задержите на пару секунд и '
        'посмотрите вдаль.',
    duration: Duration(seconds: 25),
    category: ExerciseCategory.eyes,
  ),
  Exercise(
    id: 'hands-fingers-snap',
    name: 'Щелчки пальцами',
    description:
        'По очереди соединяйте большой палец с остальными, начиная с '
        'указательного.',
    duration: Duration(seconds: 25),
    category: ExerciseCategory.hands,
  ),
  Exercise(
    id: 'body-squats',
    name: 'Полуприседы',
    description:
        'Сделайте несколько неглубоких приседаний, держа спину прямой.',
    duration: Duration(seconds: 40),
    category: ExerciseCategory.body,
  ),
  Exercise(
    id: 'eyes-letters',
    name: 'Буквы взглядом',
    description: 'Нарисуйте взглядом своё имя по стене крупными буквами.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.eyes,
  ),
  Exercise(
    id: 'hands-thumbs',
    name: 'Вращение больших пальцев',
    description:
        'Сожмите руки в кулаки и вращайте большими пальцами в обе стороны.',
    duration: Duration(seconds: 20),
    category: ExerciseCategory.hands,
  ),
  Exercise(
    id: 'body-reach',
    name: 'Потягивание вверх',
    description: 'Встаньте, поднимите руки вверх и потянитесь всем телом.',
    duration: Duration(seconds: 20),
    category: ExerciseCategory.body,
  ),
  Exercise(
    id: 'eyes-window-square',
    name: 'Квадрат на стекле',
    description:
        'Обведите взглядом угол оконной рамы по периметру, затем посмотрите '
        'вдаль.',
    duration: Duration(seconds: 25),
    category: ExerciseCategory.eyes,
  ),
  Exercise(
    id: 'hands-forearm',
    name: 'Растяжка предплечий',
    description:
        'Вытяните руку ладонью вверх и мягко потяните пальцы на себя другой '
        'рукой.',
    duration: Duration(seconds: 30),
    category: ExerciseCategory.hands,
  ),
  Exercise(
    id: 'body-march',
    name: 'Шаги на месте',
    description:
        'Пройдитесь на месте, высоко поднимая колени и свободно размахивая '
        'руками.',
    duration: Duration(seconds: 40),
    category: ExerciseCategory.body,
  ),
];
