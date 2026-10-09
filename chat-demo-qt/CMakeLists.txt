cmake_minimum_required(VERSION 3.21)
project(ChatDemoQt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Widgets)
qt_standard_project_setup()

qt_add_executable(ChatDemo src/main.cpp)

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(ChatDemo
    URI ChatDemo
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    SOURCES
        src/appdata.h
        src/models.h src/models.cpp
        src/chatstore.h src/chatstore.cpp
        src/uistatestore.h src/uistatestore.cpp
        src/windowmanager.h src/windowmanager.cpp
        src/mockserver.h src/mockserver.cpp
        src/notifier.h src/notifier.cpp
        src/selftest.h src/selftest.cpp
    QML_FILES
        qml/Main.qml
        qml/ConversationList.qml
        qml/ChatView.qml
        qml/DetachedWindow.qml
        qml/Theme.qml
        qml/MacButton.qml
        qml/Card.qml
        qml/Avatar.qml
)

target_link_libraries(ChatDemo PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)

target_include_directories(ChatDemo PRIVATE src)
set_target_properties(ChatDemo PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)  # build/ChatDemo/ 已被 QML 模块目录占用
